import 'package:anywork_client/acp.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates.dart';
import 'package:anywork_client/workspace.dart';

import '../diagnostics/contracts/timeline_diagnostics.dart';
import '../features/conversation/state/conversation_view_state.dart';
import '../features/conversation/state/plan_view_state.dart';
import '../features/conversation/state/thread_status_state.dart';

/// One request's published values. There are no repositories, VMs, observers,
/// read scopes, display leases or native handles in this object.
final class DriverSnapshot {
  DriverSnapshot({
    required this.selection,
    required this.project,
    required this.thread,
    required this.rootThreadId,
    required List<WorkspaceThreadRecord>? directory,
    required this.directoryHasMore,
    required List<AgentDirectoryEntry>? agents,
    required this.agentDirectoryError,
    required this.execution,
    required this.metrics,
    required this.context,
    required this.threadConfiguration,
    required this.authoring,
    required this.interactions,
    required this.startDraft,
    required this.composer,
    required this.configuration,
    required this.models,
    required List<OperationState> operations,
    required this.persistence,
    required this.recovery,
    required this.updates,
    required this.startup,
    required this.display,
    required this.conversation,
    required this.status,
    required this.plan,
    required this.bots,
    this.acpAuth,
    this.acpInstall,
    this.acpAccounts,
    this.templates,
  }) : directory = directory == null ? null : List.unmodifiable(directory),
       agents = agents == null ? null : List.unmodifiable(agents),
       operations = List.unmodifiable(operations);

  final WorkspaceSelection selection;
  final ProjectRecord? project;
  final WorkspaceThreadRecord? thread;
  final String? rootThreadId;
  final List<WorkspaceThreadRecord>? directory;
  final bool? directoryHasMore;
  final List<AgentDirectoryEntry>? agents;
  final StudioFailure? agentDirectoryError;
  final ThreadExecutionState? execution;
  final ThreadMetricsState? metrics;
  final ThreadContextState? context;
  final ThreadConfigurationState? threadConfiguration;
  final ThreadAuthoringState? authoring;
  final InteractionIndexReadState? interactions;
  final StartDraftState? startDraft;
  final ComposerDraftState? composer;
  final ConfigurationState configuration;
  final ModelsState models;
  final List<OperationState> operations;
  final PersistenceState persistence;
  final RecoveryState recovery;
  final UpdatesState updates;
  final StartupState startup;
  final TimelineDiagnosticsSnapshot display;
  final ConversationViewState? conversation;
  final ThreadStatusViewState? status;
  final PlanViewState? plan;
  final DriverBotsObservation bots;

  /// `acpAuth` 的 canonical 镜像；`null` 表示本 graph 尚未加载该领域。
  ///
  /// 只借用既有 `AcpAuthRepository.state` 的当前值：投影不订阅、不
  /// `synchronize()`、不启动检查，也不把空快照当成“已全部未检查”的已加载事实。
  /// 默认 `null` 让只关心其它事实的调用方不必伪造 ACP 事实，而不是提供一个
  /// “已加载的空观察”占位。
  final AcpAuthSnapshot? acpAuth;

  /// `acpInstall` 的 canonical 镜像；`null` 表示尚未加载。
  ///
  /// 与 [acpAuth] 分属两个独立资源：准备事实不能替代认证事实，`null` 也不是
  /// “全部未准备”的成功结果。阶段与失败类别都留在 typed 状态里，本层不复制判定。
  final AcpInstallSnapshot? acpInstall;

  /// Settings canonical 快照里的 ACP 接入目录；`null` 表示尚未读到该事实。
  ///
  /// ACP 账号不在 `ConfigurationState.accounts` 里，只能由设置页既有的有界读取供出；
  /// Driver 只借用已挂载 owner 的结果，不发起新读取、不维护第二份目录。
  final AcpAccountDirectory? acpAccounts;

  /// 已加载的 Native 账号模板目录；`null` 表示尚未读取。
  ///
  /// 只用于“Native 表单仍可用”的对照，Driver 不自行请求模板目录。
  final AccountTemplatesValue? templates;
}

/// The Bots adapter will consume `anywork_client/bots.dart` only after its
/// public Repository exists. Until then Unknown is not a successful empty list.
sealed class DriverBotsObservation {
  const DriverBotsObservation();
}

final class DriverBotsUnknown extends DriverBotsObservation {
  const DriverBotsUnknown(this.dependency);
  final String dependency;
}

final class DriverBotsValue extends DriverBotsObservation {
  DriverBotsValue({
    required this.revision,
    required List<DriverBotValue> bots,
    required List<DriverCredentialOperationValue> pending,
    required this.registrationAttemptId,
    required this.registrationKind,
    required this.registrationBotId,
    required this.completedBotId,
  }) : bots = List.unmodifiable(bots),
       pending = List.unmodifiable(pending);

  final int revision;
  final List<DriverBotValue> bots;
  final List<DriverCredentialOperationValue> pending;
  final String? registrationAttemptId;
  final String? registrationKind;
  final String? registrationBotId;
  final String? completedBotId;
}

final class DriverBotValue {
  const DriverBotValue({
    required this.id,
    required this.name,
    required this.enabled,
    required this.credential,
    required this.connectionKind,
    required this.pendingKind,
    required this.configCommitted,
    required this.configRevision,
    required this.trustedUserCount,
    required this.trustedGroupCount,
    required this.pairingCount,
    required this.canChangeProject,
    required this.canChangeAppId,
  });

  final String id;
  final String name;
  final bool enabled;
  final String credential;
  final String connectionKind;
  final String? pendingKind;
  final bool? configCommitted;
  final int configRevision;
  final int trustedUserCount;
  final int trustedGroupCount;
  final int pairingCount;
  final bool canChangeProject;
  final bool canChangeAppId;
}

final class DriverCredentialOperationValue {
  const DriverCredentialOperationValue({
    required this.botId,
    required this.kind,
    required this.configCommitted,
  });
  final String botId;
  final String kind;
  final bool? configCommitted;
}
