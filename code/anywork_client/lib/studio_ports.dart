import 'dart:async';
import 'dart:typed_data';

import 'models.dart';
import 'src/modes/modes_ports.dart';
import 'transport_ports.dart';
import 'src/studio/bootstrap.dart';

export 'src/modes/modes_ports.dart';
export 'src/studio/thread_frames.dart';
export 'src/conversation/domain/conversation_models.dart';
export 'src/studio/bootstrap.dart';

abstract interface class RuntimeTransport {
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic);
}

abstract interface class AttachmentTransport {
  Future<List<AttachmentDraftView>> admitAttachmentDrafts(
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  );
  Future<bool> removeAttachmentDraft(String draftId);
  Future<Uint8List> readAttachmentDraft(String draftId);
  Future<Uint8List> readThreadAttachment(String threadId, String attachmentId);
}

abstract interface class BootstrapTransport {
  Future<StudioBootstrap> readBootstrap();
}

abstract interface class CommandTransport {
  /// 精确停止一个已观察到的执行。
  ///
  /// 目标身份由调用方从规范投影冻结（主会话取自身运行时执行，成员行取智能体目录），
  /// 不按执行时的当前状态重定向。受理不等于已经结束。
  Future<StopThreadCommandReply> stopThread(
    String threadId,
    String executionId, {
    required OperationId operationId,
  });

  /// 无新内容继续主会话。
  ///
  /// 只接受主会话目标；子会话继续由主智能体调度。受理不等于新轮次已开始。
  Future<ContinueThreadCommandReply> continueThread(
    String threadId,
    String continuationId, {
    required int expectedModelRouteRevision,
    required OperationId operationId,
  });
  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  });

  /// 按原操作身份回查一次继续操作的受理与消费事实；查询不激活执行。
  Future<ContinuationOperationView> readContinuationOperation(
    String threadId,
    String operationId,
  );

  /// 主会话可见的子任务待决交互；列举不激活任何子会话。
  Future<List<ChildInteractionSummary>> readChildInteractions(String threadId);
}

/// 按需读取进程级持久化队列压力的可选能力。
///
/// 队列压力（排队操作数、字节、最老待保存年龄、在途字节与最近错误）是诊断观测，不是权威
/// 会话状态。实现本能力的 API 从后端持久化协调器读取真实值；未实现该能力的 API（例如测试
/// 替身）不提供该观测，调用方据此显示为未知，而不是编造本地推算值。
///
/// `readPersistenceQueueState` 返回 typed wrapper（发布 revision + 时间基线）；
/// `readPersistenceQueue` 是旧 raw 观测的兼容视图，仅解包 wrapper，不另立事实源。
abstract interface class PersistenceQueueReader {
  Future<PersistenceQueueStateView> readPersistenceQueueState();

  Future<PersistenceQueueSnapshot> readPersistenceQueue();
}

abstract class StudioTransport
    implements
        RuntimeTransport,
        AttachmentTransport,
        BootstrapTransport,
        ConversationTransport,
        CommandTransport,
        ModeEditorTransport {
  /// Exit admission belongs to this application transport instance.
  void sealForShutdown() {}
  Future<List<StudioShutdownIssue>> cancelDartSubscriptions({
    required int budgetMs,
  }) async => const [];

  Future<RecoveryStateSnapshot> retryRecovery();

  /// 配置级 Agent Profiles 的 canonical 资源快照（含 revision 与逐文件诊断）。
  Future<AgentProfilesStateView> readAgentProfilesState();

  /// 兼容视图：从 [readAgentProfilesState] 解包 Profile 列表。
  ///
  /// 设置页已由 AgentProfiles topic 驱动；本方法仅供尚未迁移的一次性读取，
  /// 不是第二事实源。
  Future<List<AgentProfileView>> readAgentProfiles();
  Future<SettingsCommandReply> setSystemAgentEnabled({
    required OperationId operationId,
    required int expectedSettingsRevision,
    required String profileId,
    required bool enabled,
  });
  Future<SettingsCommandReply> saveUserAgentProfile(
    int expectedSettingsRevision,
    AgentProfileDraft draft, {
    required OperationId operationId,
  });
  Future<void> cleanupPreservedWorktree({
    required String ownerKind,
    required String ownerThreadId,
    required int expectedLeaseRevision,
  });
  Future<StudioBootstrap> readBootstrap();
  Future<ThreadDirectoryPage> listThreadsPage({String? cursor, int limit = 50});
  Future<ThreadDirectoryPage> queryThreads(
    DirectoryQuery query, {
    String? cursor,
    int limit = 50,
  });
  Future<StudioThread> restoreThread(String threadId);

  /// Reads saved/live metadata for one explicitly selected member without
  /// activating its execution owner or subscribing other child histories.
  Future<StudioThread> readThread(String threadId);
  Future<void> activateProject(String workspaceId);
  Future<StudioProject> openProject(String path);

  /// Prepares standalone drafts and returns the versioned canonical directory.
  /// Does not create a Thread or fabricate a client-owned directory revision.
  Future<ProjectDirectoryState> prepareStandaloneWorkspace();
  Future<StudioProject> renameProject(String workspaceId, String name);
  Future<List<SshServer>> listSshServers();
  Future<SshServer> saveSshServer(SaveSshServerCommand command);
  Future<void> deleteSshServer(String alias);
  Future<SshConnectionView> authenticateSshServer(
    AuthenticateSshServerCommand command,
  );
  Future<SshConnectionView> testSshConnection(String alias);
  Future<SshConnectionView> reconnectSshServer(String alias);
  Future<RemoteDirectoryListing> browseRemoteDirectories(
    String alias, {
    String? path,
    String? cursor,
  });
  Future<void> closeRemoteDirectory(String alias, String cursor);
  Future<StudioProject> openRemoteProject(String alias, String path);

  /// One creation command, with progress followed by exactly one terminal outcome.
  /// EOF or a transport error before that outcome does not prove rejection.
  Stream<NewThreadStartEvent> startNewThread(
    String workspaceId,
    StudioPromptInput input,
    ThreadModeId mode, {
    required ModeModelRouteView route,
    required DelegationMode delegationMode,
    required DelegationPreference delegationPreference,
    String? workspaceMode,
  });
  Future<RenameThreadCommandReply> renameThread(
    String threadId,
    String title, {
    required OperationId operationId,
  });
  Future<ArchiveThreadCommandReply> archiveThread(
    String threadId, {
    required OperationId operationId,
  });
  Future<void> archiveProject(String workspaceId);
  Future<PersistenceStateSnapshot> retryPersistence();

  /// 重试保存的命令响应仍是 raw 队列观测（不带发布 revision）：不伪造领域水位，
  /// typed 更新由 PersistenceQueue topic 的后续事件交付。
  Future<PersistenceQueueSnapshot> retryThreadHistory(
    String threadId,
    int faultGeneration,
  );

  /// 显式继续：在保存重试已按同一代数确认后再解除准入闩。
  ///
  /// 与 [retryThreadHistory] 是两个动作：重试只把积压事实写下去，本命令才恢复执行。
  /// 代数过期、后端仍在上报故障或仍有未上交批次时后端会拒绝，调用方按 typed 存储状态重试，
  /// 绝不本地假定成功或自动恢复。
  Future<PersistenceQueueSnapshot> resumeThreadHistory(
    String threadId,
    int faultGeneration,
  );
  Future<ThreadModelRouteCommandReply> setThreadModelRoute({
    required OperationId operationId,
    required String threadId,
    required int expectedModelRouteRevision,
    required int expectedSettingsRevision,
    required String accountId,
    required String modelId,
    String? effort,
  });
  Future<void> compactThread(String threadId);

  Future<ThreadModeCommandReply> setThreadMode({
    required OperationId operationId,
    required String threadId,
    required ThreadModeId mode,
  });

  /// 订阅一个 typed 产品 topic；一次订阅只观察一个领域。
  ///
  /// 首帧是 register receiver 之后读取的 canonical Baseline（含领域 revision），
  /// 随后是携带领域 revision 的 owner 事件；`Lagged` 表示无法证明增量连续，调用方
  /// 只重建该 topic（cancel 后重新订阅、以新 Baseline 首帧恢复），不做全量重读。
  Stream<ProductTopicFrame> subscribeProductTopic(ProductTopic topic);

  Stream<StudioShutdownProgress> subscribeShutdownProgress();

  /// 早期退出封闭（Rust 侧唯一权威入口）。
  ///
  /// 必须在任何 Dart 外部取消等待之前调用：它同步封闭单向退出闩并广播一次取消，使迟到
  /// 初始化 / 安装无法再发布 runtime，且**不**触发初始化、**不** stop/join 真正资源、
  /// **不**发布 `Stopped`。真正的资源收束与 finalize 只在后续 `shutdownRuntime` 里发生。
  ///
  /// [remainingMs] 是 native 宿主剩余清理预算（唯一 30s 期限减已消耗时间，最多 28s），
  /// 不是新的窗口；bridge 侧按 `min(remaining, 28s)` 收敛，首次生效、重复调用不延长。
  /// 未加载 runtime 无 owner 时跳过。失败/超时由调用方保留为 external issue 继续收尾。
  Future<void> beginRuntimeExit({required int remainingMs});

  /// 关闭 runtime 并返回 typed 报告。
  ///
  /// [remainingMs] 是 native 宿主剩余清理预算（上限 28 秒）。[externalIssues] 是 Dart
  /// 拥有的外部 owner（产品/Thread 流、关机进度流）在本次预算内收束得到的 typed issue，
  /// 作为本次关闭的最终成功前置条件随请求交给 runtime 单编排；默认空表示调用方已确保无
  /// 外部问题。只有真实 `Clean` 才代表持久化已安全排空；`Degraded` 或超时不代表保存成
  /// 功，调用方据此决定退出码。Cleanup 失败时保留 native owner 并把错误抛给调用方。
  Future<StudioExitReport> shutdownRuntime({
    required int remainingMs,
    List<StudioShutdownIssue> externalIssues = const [],
    StudioExitIntent intent = StudioExitIntent.exit,
  });

  Future<SubmitPromptReceipt> submitPrompt(
    String threadId,
    StudioPromptInput input, {
    required int expectedModelRouteRevision,
  });
  Future<List<AttachmentDraftView>> admitAttachmentDrafts(
    AttachmentAdmissionContext context,
    List<AttachmentDraftSource> sources,
  );
  Future<bool> removeAttachmentDraft(String draftId);
  Future<Uint8List> readAttachmentDraft(String draftId);
  Future<Uint8List> readThreadAttachment(String threadId, String attachmentId);
  Future<StopThreadCommandReply> stopThread(
    String threadId,
    String executionId, {
    required OperationId operationId,
  });
  Future<ContinueThreadCommandReply> continueThread(
    String threadId,
    String continuationId, {
    required int expectedModelRouteRevision,
    required OperationId operationId,
  });
  Future<ContinuationOperationView> readContinuationOperation(
    String threadId,
    String operationId,
  );
  Future<List<ChildInteractionSummary>> readChildInteractions(String threadId);

  /// 在一个宿主会话名义下决议交互。
  ///
  /// 主会话决议自己的交互时 [hostThreadId] 就是该会话；主会话转交子任务问题时它仍是主会话，
  /// 原交互身份与 [expectedRevision] 原样透传，决议结果落在原交互所属会话。
  Future<InteractionCommandReply> respondInteraction(
    String hostThreadId,
    String interactionId,
    int expectedRevision,
    InteractionResolutionCommand resolution, {
    required OperationId operationId,
  });
  Future<SettingsCommandReply> saveRuntimePermissionMode(
    int expectedSettingsRevision,
    PermissionMode mode, {
    required OperationId operationId,
  });
  Future<DelegationModelList> listDelegationModels(
    ListDelegationModelsRequest request,
  );
  Future<DelegationModelDetail> getDelegationModel(DelegationModelKey key);
  Future<SettingsCommandReply> applySettingsField(
    int expectedSettingsRevision,
    SettingsFieldCommand command, {
    required OperationId operationId,
  });

  /// 重新读取 backend canonical settings 快照（不依赖本地缓存）。
  Future<SettingsStateSnapshot> readSettingsState();
  Future<SkillsStateSnapshot> readSkillsState(String workspaceId);
  Future<SkillsStateSnapshot> discoverSkills(String workspaceId);
  Future<SkillSearchResultView> searchSkills(
    String workspaceId,
    String query, {
    int limit = 50,
  });
  Future<McpStateSnapshot> readMcpState();
  Future<McpStateSnapshot> resetMcpServer(String serverId);
  Future<McpStateSnapshot> resetAllMcp();
  Future<LspStateSnapshot> readLspState();
  Future<LspStateSnapshot> probeLspServer(String workspaceId);
  Future<LspStateSnapshot> repairLspServer(String workspaceId, String serverId);
  Future<LspStateSnapshot> resetLspServer(String workspaceId, String serverId);
  Future<LspStateSnapshot> resetLspWorkspace(String workspaceId);

  Future<BotsStateSnapshot> readBots();
  Future<BotsCommandReply> saveBot(SaveBotRequest request);
  Future<BotsCommandReply> startBotRegistration(
    StartBotRegistrationRequest request,
  );
  Future<BotsCommandReply> cancelBotRegistration(
    CancelBotRegistrationRequest request,
  );
  Future<BotsCommandReply> setBotEnabled(SetBotEnabledRequest request);
  Future<BotsCommandReply> retryBotConnection(
    RetryBotConnectionRequest request,
  );
  Future<BotsCommandReply> setBotTrustedUser(SetBotTrustedUserRequest request);
  Future<BotsCommandReply> setBotTrustedChat(SetBotTrustedChatRequest request);
  Future<BotConversationPage> listBotConversations(
    ListBotConversationsRequest request,
  );
  Future<BotMessagePage> readBotMessages(ReadBotMessagesRequest request);
  Future<BotSendResult> sendBotMessage(SendBotMessageRequest request);
  Future<BotConversationThreadReply> createBotConversationThread(
    CreateBotConversationThreadRequest request,
  );
}

/// Update commands return Rust-owned canonical snapshots; application routing
/// and opening external URLs remain host actions.
abstract interface class StudioUpdateApi {
  Future<UpdaterStateSnapshot> read();
  Future<UpdaterStateSnapshot> check();
  Future<void> startAutomaticUpdate();
  Future<void> cancelAutomaticUpdate();
  Future<StudioUpdateOperation> startPreparation({
    required int expectedRevision,
    required String version,
  });
}

/// The backend rejected preparation before creating an operation. A lost or
/// undecodable transport reply must never be represented by this exception.
final class StudioUpdatePreparationRejected implements Exception {
  const StudioUpdatePreparationRejected(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A strong owner of one preparation and its ordered progress observer.
abstract interface class StudioUpdateOperation {
  Stream<UpdaterStateSnapshot> get events;
  Future<void> cancel();
  Future<void> finishPreparation();

  /// Releases the already joined transport handle; it does not join tasks.
  void dispose();
}
