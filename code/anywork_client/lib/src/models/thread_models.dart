import 'attachment_models.dart';
import 'composer_models.dart';
import 'interaction_models.dart';
import 'runtime_models.dart';
import 'studio_enums.dart';
import 'thread_activity_models.dart';
import 'thread_directory_models.dart';
import 'timeline_models.dart' show TimelineTodoListUpdate;
import 'turn_models.dart';

enum ThreadTextChannel { user, parentAgent, commentary, finalAnswer }

class ThreadAttachmentView {
  const ThreadAttachmentView({
    required this.id,
    required this.modality,
    required this.mediaType,
    required this.byteSize,
    this.filename,
    this.width,
    this.height,
  });

  final String id;
  final AttachmentModalityView modality;
  final String mediaType;
  final String? filename;
  final int? width;
  final int? height;
  final int byteSize;
}

/// 内容字段身份（与后端 `BridgeContentField` 一一对应）。
///
/// 身份只由字段判别式决定，**不**从内容字符串推断：正文落在哪个 domain 字段完全由这里
/// 指定。推理分块用逻辑 `chunkIndex` 保持块身份，删除一块不会让其它块移动。
sealed class ThreadContentFieldView {
  const ThreadContentFieldView();

  /// 值语义键：判别分支 + 逻辑索引（分块、payload、问答位置与子字段）。
  ///
  /// 字段身份是**值**，不是对象实例：FRB 每帧解码出的参数化字段都是新实例，独立解码的
  /// 同值字段必须相等，否则详情引用表会随帧增长（design/26 §26.7）。
  Object get identityKey;

  @override
  bool operator ==(Object other) =>
      other is ThreadContentFieldView && other.identityKey == identityKey;

  @override
  int get hashCode => identityKey.hashCode;
}

final class ThreadTextFieldView extends ThreadContentFieldView {
  const ThreadTextFieldView();

  @override
  Object get identityKey => (ThreadTextFieldView,);
}

final class ThreadThinkingSummaryFieldView extends ThreadContentFieldView {
  const ThreadThinkingSummaryFieldView(this.chunkIndex);
  final int chunkIndex;

  @override
  Object get identityKey => (ThreadThinkingSummaryFieldView, chunkIndex);
}

final class ThreadThinkingContentFieldView extends ThreadContentFieldView {
  const ThreadThinkingContentFieldView(this.chunkIndex);
  final int chunkIndex;

  @override
  Object get identityKey => (ThreadThinkingContentFieldView, chunkIndex);
}

final class ThreadToolArgumentsFieldView extends ThreadContentFieldView {
  const ThreadToolArgumentsFieldView();

  @override
  Object get identityKey => (ThreadToolArgumentsFieldView,);
}

final class ThreadToolResultFieldView extends ThreadContentFieldView {
  const ThreadToolResultFieldView();

  @override
  Object get identityKey => (ThreadToolResultFieldView,);
}

/// 工具一次执行附加的开放产物正文：只在 canonical 映射与详情查看边界编码。
///
/// 预览里的产物数组可以为空而原文仍然存在；只要本字段的详情引用还在，消费者就保留按需
/// 读取入口，不能按预览数组长度判断“没有产物”。
final class ThreadToolOutputArtifactsFieldView extends ThreadContentFieldView {
  const ThreadToolOutputArtifactsFieldView();

  @override
  Object get identityKey => (ThreadToolOutputArtifactsFieldView,);
}

/// 原始记录的一段正文：`payloadIndex` 是它在原记录里的顺序。
final class ThreadRawPayloadFieldView extends ThreadContentFieldView {
  const ThreadRawPayloadFieldView(this.payloadIndex);
  final int payloadIndex;

  @override
  Object get identityKey => (ThreadRawPayloadFieldView, payloadIndex);
}

/// 普通问答正文域：问题位置 + 该问题内的一段可展示正文。
///
/// 问答的标题、问题、选项与答案共享同一条内容预算，因此身份必须细到"哪一段"，而不是整条问答。
final class ThreadToolUserInputFieldView extends ThreadContentFieldView {
  const ThreadToolUserInputFieldView({
    required this.questionIndex,
    required this.part,
  });

  final int questionIndex;
  final ThreadUserInputFieldPartView part;

  @override
  Object get identityKey =>
      (ThreadToolUserInputFieldView, questionIndex, part.identityKey);
}

/// 普通问答投影里一段可展示正文的位置（与后端 `BridgeThreadUserInputFieldPart` 一一对应）。
sealed class ThreadUserInputFieldPartView {
  const ThreadUserInputFieldPartView();

  /// 值语义键：判别分支 + 选项/答案索引。
  Object get identityKey;

  @override
  bool operator ==(Object other) =>
      other is ThreadUserInputFieldPartView && other.identityKey == identityKey;

  @override
  int get hashCode => identityKey.hashCode;
}

final class ThreadUserInputHeaderFieldPartView
    extends ThreadUserInputFieldPartView {
  const ThreadUserInputHeaderFieldPartView();

  @override
  Object get identityKey => (ThreadUserInputHeaderFieldPartView,);
}

final class ThreadUserInputQuestionFieldPartView
    extends ThreadUserInputFieldPartView {
  const ThreadUserInputQuestionFieldPartView();

  @override
  Object get identityKey => (ThreadUserInputQuestionFieldPartView,);
}

final class ThreadUserInputAnswerFieldPartView
    extends ThreadUserInputFieldPartView {
  const ThreadUserInputAnswerFieldPartView(this.answerIndex);
  final int answerIndex;

  @override
  Object get identityKey => (ThreadUserInputAnswerFieldPartView, answerIndex);
}

final class ThreadUserInputOptionLabelFieldPartView
    extends ThreadUserInputFieldPartView {
  const ThreadUserInputOptionLabelFieldPartView(this.optionIndex);
  final int optionIndex;

  @override
  Object get identityKey =>
      (ThreadUserInputOptionLabelFieldPartView, optionIndex);
}

final class ThreadUserInputOptionDescriptionFieldPartView
    extends ThreadUserInputFieldPartView {
  const ThreadUserInputOptionDescriptionFieldPartView(this.optionIndex);
  final int optionIndex;

  @override
  Object get identityKey =>
      (ThreadUserInputOptionDescriptionFieldPartView, optionIndex);
}

/// 一个字段的 typed 变化（与后端 `BridgeFieldChange` 一一对应）。
///
/// [`Append`] 只在前缀仍有效时到达，追加到本地已交付末尾；[`Replace`] 是权威替换（含
/// 预览升级为完整正文）；[`Remove`] 丢弃该字段的本地副本；[`Unchanged`] 正文不动，但所属
/// 条目的 revision / omitted / 保存水位仍要在整组应用后提交。
sealed class ThreadFieldChangeView {
  const ThreadFieldChangeView();
}

final class UnchangedThreadFieldChangeView extends ThreadFieldChangeView {
  const UnchangedThreadFieldChangeView();
}

final class AppendThreadFieldChangeView extends ThreadFieldChangeView {
  const AppendThreadFieldChangeView(this.text);
  final String text;
}

final class ReplaceThreadFieldChangeView extends ThreadFieldChangeView {
  const ReplaceThreadFieldChangeView(this.text);
  final String text;
}

final class RemoveThreadFieldChangeView extends ThreadFieldChangeView {
  const RemoveThreadFieldChangeView();
}

/// 同一 item 的一个字段变化；一次 `UpdateItem` 携带整组，**原子应用后一次提交**版本。
sealed class ThreadContentLifecycleView {
  const ThreadContentLifecycleView();

  String get status => switch (this) {
    StreamingThreadContentView() => 'streaming',
    CompletedThreadContentView() => 'completed',
    FailedThreadContentView() => 'failed',
    CancelledThreadContentView() => 'cancelled',
  };

  bool get isTerminal => this is! StreamingThreadContentView;

  DateTime? get terminalAt => switch (this) {
    StreamingThreadContentView() => null,
    CompletedThreadContentView(:final completedAt) => completedAt,
    FailedThreadContentView(:final failedAt) => failedAt,
    CancelledThreadContentView(:final cancelledAt) => cancelledAt,
  };

  String? get failure => switch (this) {
    FailedThreadContentView(:final error) => error,
    StreamingThreadContentView() ||
    CompletedThreadContentView() ||
    CancelledThreadContentView() => null,
  };
}

final class StreamingThreadContentView extends ThreadContentLifecycleView {
  const StreamingThreadContentView();
}

final class CompletedThreadContentView extends ThreadContentLifecycleView {
  const CompletedThreadContentView(this.completedAt);
  final DateTime completedAt;
}

final class FailedThreadContentView extends ThreadContentLifecycleView {
  const FailedThreadContentView(this.failedAt, this.error);
  final DateTime failedAt;
  final String error;
}

final class CancelledThreadContentView extends ThreadContentLifecycleView {
  const CancelledThreadContentView(this.cancelledAt, this.reason);
  final DateTime cancelledAt;
  final String reason;
}

sealed class ThreadItemStateView {
  const ThreadItemStateView();
}

final class ThreadSkillItemStateView extends ThreadItemStateView {
  const ThreadSkillItemStateView({
    required this.name,
    required this.source,
    required this.providerId,
    required this.resourceBase,
    required this.cause,
    required this.activatedAt,
  });

  final String name;
  final String source;
  final String providerId;
  final SkillResourceBaseView resourceBase;
  final SkillActivationCauseView cause;
  final DateTime activatedAt;
}

enum SkillResourceBaseKind { directory, url, opaque }

class SkillResourceBaseView {
  const SkillResourceBaseView(this.kind, this.value);
  final SkillResourceBaseKind kind;
  final String value;
}

enum SkillActivationCauseKind { tool, userGesture }

class SkillActivationCauseView {
  const SkillActivationCauseView(this.kind, this.id);
  final SkillActivationCauseKind kind;
  final String id;
}

/// 计划确认回执的权威决定。
///
/// 只由该交互自己的已接受答案派生：`resolved` 表示交互已有回答，但回答里没有本版本
/// 认识的决定标记。后一种情况既不猜测批准也不猜测修改，只保留已回答这一事实。
enum PlanConfirmationDecisionView {
  pending,
  approved,
  revisionRequested,
  cancelled,
  resolved,
}

/// 计划确认的只读历史回执。
///
/// 来源是发起 `plan_submit` 的工具条目携带的同一 typed 问答投影：唯一
/// [agentSessionPlanConfirmationQuestionId] 问题标识计划语义，答案列表保留批准/修订
/// 决定与用户原始反馈。GUI 只把 [decision] 映射成本地化状态，不显示内部标记。
final class PlanConfirmationReceiptView {
  PlanConfirmationReceiptView({
    required this.interactionId,
    required this.title,
    required this.decision,
    Iterable<String> feedback = const [],
  }) : feedback = List.unmodifiable(feedback);

  final String interactionId;

  /// 计划标题（问题正文的一级标题），缺失时退回问题 header。
  final String title;

  final PlanConfirmationDecisionView decision;

  /// 用户原始反馈，按原顺序保留；批准与未知标记不产生反馈正文。
  final List<String> feedback;

  bool get isResolved => decision != PlanConfirmationDecisionView.pending;
}

enum ThreadToolFailureKindView { execution, timedOut, budgetLimited }

class ThreadToolFailureView {
  const ThreadToolFailureView({required this.kind, required this.message});
  final ThreadToolFailureKindView kind;
  final String message;
}

class ThreadAgentIdentityView {
  const ThreadAgentIdentityView({
    required this.id,
    required this.path,
    required this.role,
    required this.task,
    required this.depth,
    this.parentPath,
  });

  final String id;
  final String path;
  final String? parentPath;
  final String role;
  final String task;
  final int depth;
}

sealed class ThreadAgentLifecycleView {
  const ThreadAgentLifecycleView();
}

final class QueuedThreadAgentView extends ThreadAgentLifecycleView {
  const QueuedThreadAgentView();
}

final class RunningThreadAgentView extends ThreadAgentLifecycleView {
  const RunningThreadAgentView();
}

final class SucceededThreadAgentView extends ThreadAgentLifecycleView {
  const SucceededThreadAgentView(this.completedAt, this.summary);
  final DateTime completedAt;
  final String summary;
}

final class DeniedThreadAgentView extends ThreadAgentLifecycleView {
  const DeniedThreadAgentView(this.deniedAt, this.reason);
  final DateTime deniedAt;
  final String reason;
}

final class CancelledThreadAgentView extends ThreadAgentLifecycleView {
  const CancelledThreadAgentView(this.cancelledAt, this.reason);
  final DateTime cancelledAt;
  final String reason;
}

final class FailedThreadAgentView extends ThreadAgentLifecycleView {
  const FailedThreadAgentView(this.failedAt, this.error);
  final DateTime failedAt;
  final String error;
}

final class ThreadAgentItemStateView extends ThreadItemStateView {
  const ThreadAgentItemStateView({
    required this.identity,
    required this.lifecycle,
  });
  final ThreadAgentIdentityView identity;
  final ThreadAgentLifecycleView lifecycle;
}

final class ThreadTurnItemStateView extends ThreadItemStateView {
  const ThreadTurnItemStateView(this.state, {this.inputId});
  final StudioTurnState state;
  final String? inputId;
}

sealed class ThreadInferenceLifecycleView {
  const ThreadInferenceLifecycleView();
}

final class RunningThreadInferenceView extends ThreadInferenceLifecycleView {
  const RunningThreadInferenceView();
}

final class CompletedThreadInferenceView extends ThreadInferenceLifecycleView {
  const CompletedThreadInferenceView(this.completedAt, this.usage);
  final DateTime completedAt;
  final ThreadInferenceUsageView usage;
}

class ThreadInferenceUsageView {
  const ThreadInferenceUsageView({
    required this.promptTokens,
    required this.completionTokens,
    required this.cachedPromptTokens,
    required this.totalTokens,
  });
  final int promptTokens;
  final int completionTokens;
  final int cachedPromptTokens;
  final int totalTokens;
}

final class FailedThreadInferenceView extends ThreadInferenceLifecycleView {
  const FailedThreadInferenceView(this.failedAt, this.error);
  final DateTime failedAt;
  final String error;
}

final class CancelledThreadInferenceView extends ThreadInferenceLifecycleView {
  const CancelledThreadInferenceView(this.cancelledAt, this.reason);
  final DateTime cancelledAt;
  final String reason;
}

final class ThreadInferenceItemStateView extends ThreadItemStateView {
  const ThreadInferenceItemStateView({
    required this.inferenceId,
    required this.model,
    required this.lifecycle,
  });
  final String inferenceId;
  final String model;
  final ThreadInferenceLifecycleView lifecycle;
}

/// 一条 raw 记录的来源；载荷列表不能区分这两类。
enum ThreadRawItemOrigin {
  /// 无法解码成 typed 条目、按原样保留的历史载荷。
  stored,

  /// 替代无正文控制输入的运行时说明，本身不含可展开内容。
  runtimeControl,
}

final class ThreadFileItemStateView extends ThreadItemStateView {
  const ThreadFileItemStateView(this.path, this.mediaType, this.completedAt);
  final String path;
  final String? mediaType;
  final DateTime completedAt;
}

final class ThreadContextCompactionItemStateView extends ThreadItemStateView {
  const ThreadContextCompactionItemStateView(
    this.beforeTokens,
    this.afterTokens,
    this.compactedAt,
  );
  final int? beforeTokens;
  final int? afterTokens;
  final DateTime compactedAt;
}

/// 合并已采纳 Turn 事实与候选 Turn 的唯一共享规则。
///
/// [StudioTurnView.revision] 来自同一 Thread 的 core commit sequence，可跨
/// Turn 身份比较；不是每 Turn 局部计数，也不跨 Thread 比较。只有候选
/// revision 严格大于已采纳值才替换，小于或等于一律保留已采纳值，相同修订的
/// 不同身份不制造额外顺序，[StudioTurnView.updatedAt] 不参与比较。同一
/// Turn 身份上已采纳的终态事实不可被 busy 候选回退。
StudioTurnView? newestSessionTurn(
  StudioTurnView? alreadyAdopted,
  StudioTurnView? candidate,
) {
  if (alreadyAdopted == null) return candidate;
  if (candidate == null) return alreadyAdopted;
  if (alreadyAdopted.turnId == candidate.turnId &&
      alreadyAdopted.state.isTerminal &&
      candidate.state.isBusy) {
    return alreadyAdopted;
  }
  return candidate.revision > alreadyAdopted.revision
      ? candidate
      : alreadyAdopted;
}

class ThreadWorkspace {
  const ThreadWorkspace({
    required this.thread,
    required this.revision,
    required this.interactions,
    required this.runtime,
    this.activeTurn,
    this.latestTurn,
    this.todo,
    this.activity,
    this.storage,
  });

  /// Thread 身份；由 Thread directory 重绑，不作为 mode/role/status 的事实源。
  final StudioThread thread;

  /// 当前状态 revision（snapshot 与实时事件共用）；历史页 watermark 不属于它。
  final int revision;

  final List<PendingInteraction> interactions;
  final ThreadRuntimeView runtime;

  /// 当前执行中的 Turn；Terminal Turn 不留在当前状态里。
  final StudioTurnView? activeTurn;

  /// 最近一次已知 Turn 事实（live turn 通知）。
  final StudioTurnView? latestTurn;

  final TimelineTodoListUpdate? todo;

  /// 后端 typed 当前活动投影；`null` 表示当前没有活动。独立于消息窗口。
  final ThreadActivityView? activity;

  /// 后端 typed 存储状态；`null` 表示没有可报告的存储事实（不是“健康”）。
  final ThreadStorageStateView? storage;

  /// 最近 Turn 事实：当前执行的 Turn 不早于已观测到的终态 Turn。
  StudioTurnView? get lastTurn => newestSessionTurn(latestTurn, activeTurn);

  ThreadWorkspace copyWith({
    StudioThread? thread,
    int? revision,
    List<PendingInteraction>? interactions,
    ThreadRuntimeView? runtime,
    Object? activeTurn = _workspaceUnset,
    Object? latestTurn = _workspaceUnset,
    Object? todo = _workspaceUnset,
    Object? activity = _workspaceUnset,
    Object? storage = _workspaceUnset,
  }) {
    return ThreadWorkspace(
      thread: thread ?? this.thread,
      revision: revision ?? this.revision,
      interactions: interactions ?? this.interactions,
      runtime: runtime ?? this.runtime,
      activeTurn: identical(activeTurn, _workspaceUnset)
          ? this.activeTurn
          : activeTurn as StudioTurnView?,
      latestTurn: identical(latestTurn, _workspaceUnset)
          ? this.latestTurn
          : latestTurn as StudioTurnView?,
      todo: identical(todo, _workspaceUnset)
          ? this.todo
          : todo as TimelineTodoListUpdate?,
      activity: identical(activity, _workspaceUnset)
          ? this.activity
          : activity as ThreadActivityView?,
      storage: identical(storage, _workspaceUnset)
          ? this.storage
          : storage as ThreadStorageStateView?,
    );
  }
}

class WorkspaceUiState {
  const WorkspaceUiState({
    this.composer = const ComposerThreadState.idle(),
    this.syncState = AgentWorkspaceSyncState.loading,
    this.loadError,
    this.subscriptionGeneration = 0,
    this.activityDetail = const ThreadActivityDetailState(),
  });

  final ComposerThreadState composer;
  final AgentWorkspaceSyncState syncState;
  final String? loadError;
  final int subscriptionGeneration;

  /// 按活动身份缓存的完整详情读取状态；身份变化即失效。
  final ThreadActivityDetailState activityDetail;

  WorkspaceUiState copyWith({
    ComposerThreadState? composer,
    AgentWorkspaceSyncState? syncState,
    String? loadError,
    int? subscriptionGeneration,
    ThreadActivityDetailState? activityDetail,
  }) {
    return WorkspaceUiState(
      composer: composer ?? this.composer,
      syncState: syncState ?? this.syncState,
      loadError:
          syncState == AgentWorkspaceSyncState.loading ||
              syncState == AgentWorkspaceSyncState.ready
          ? null
          : loadError ?? this.loadError,
      subscriptionGeneration:
          subscriptionGeneration ?? this.subscriptionGeneration,
      activityDetail: activityDetail ?? this.activityDetail,
    );
  }
}

/// 固定活动条展开详情的一次按需读取状态。
///
/// 以活动身份 + 版本为键：同一身份内版本前进即视为需要刷新；身份变化即失效。
/// 读取在途时只保留一个请求（调用方合并），旧身份的迟到结果不得覆盖新身份。
class ThreadActivityDetailState {
  const ThreadActivityDetailState({
    this.identity,
    this.revision = 0,
    this.loading = false,
    this.detail,
    this.error,
  });

  final String? identity;
  final int revision;
  final bool loading;
  final ThreadActivityDetail? detail;
  final String? error;

  bool matches(String identity) => this.identity == identity;

  /// 当前缓存是否已对同一身份的最新版本有效（无需重读）。
  bool covers(String identity, int revision) {
    if (identity.isEmpty || this.identity != identity) return false;
    if (loading) return true;
    return (detail != null || error != null) && this.revision >= revision;
  }

  ThreadActivityDetailState copyWith({
    Object? identity = _workspaceUnset,
    int? revision,
    bool? loading,
    Object? detail = _workspaceUnset,
    Object? error = _workspaceUnset,
  }) {
    return ThreadActivityDetailState(
      identity: identical(identity, _workspaceUnset)
          ? this.identity
          : identity as String?,
      revision: revision ?? this.revision,
      loading: loading ?? this.loading,
      detail: identical(detail, _workspaceUnset)
          ? this.detail
          : detail as ThreadActivityDetail?,
      error: identical(error, _workspaceUnset) ? this.error : error as String?,
    );
  }
}

const _workspaceUnset = Object();
