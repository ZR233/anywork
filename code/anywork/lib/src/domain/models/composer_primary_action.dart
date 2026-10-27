import 'package:anywork_client/models.dart';

/// 主会话输入区唯一主按钮的语义状态。
///
/// 只由 canonical 事实推导：会话当前执行身份、继续点、草稿内容、已受理的停止/继续
/// 意图与类型化阻塞原因。不从最后一条消息、轮次终态或按钮点击记忆推断能否继续；
/// 展示层只负责把 [ComposerPrimaryAction.kind] 与 [ComposerPrimaryAction.blocker]
/// 映射成自己的图标与文案（design/19 §19.11、design/25 §25.7）。
enum ComposerPrimaryActionKind {
  /// 子会话：没有输入区操作，只读展示。
  readOnly,

  /// 运行中且无草稿内容：中性停止。
  stop,

  /// 运行中或有未认领继续点且已有内容：发送并继续。
  sendAndContinue,

  /// 停止已受理、清理未结束：禁用“正在停止”。
  stopping,

  /// 有未认领继续点且无内容：必须显式点击的“继续”。
  continueConversation,

  /// 继续已受理或仍在准备、等待准入：禁用“正在继续”。
  continuing,

  /// 普通发送。
  send,
}

/// 主按钮被堵塞的类型化原因。
///
/// 具体文案由展示层按应用语言映射；这里只保留可判定的领域事实，避免把 UI 文本
/// 写进状态机，也避免用错误字符串反推原因。
sealed class ComposerBlocker {
  const ComposerBlocker();

  /// 是否阻塞提交与继续。
  ///
  /// 保存、模型与工作区是不可绕过的前置条件；后端明确拒绝的原因是**上一次尝试的
  /// 结果**，必须继续显示，但不能因此禁止用户显式重试（否则一次过时点击会把入口
  /// 永久锁死）。
  bool get blocksSubmission;
}

/// 保存（持久化）尚未完成、处于压力暂停或硬故障仍闩住准入。
final class ComposerStorageBlocker extends ComposerBlocker {
  const ComposerStorageBlocker();

  @override
  bool get blocksSubmission => true;

  @override
  bool operator ==(Object other) => other is ComposerStorageBlocker;

  @override
  int get hashCode => (ComposerStorageBlocker).hashCode;
}

/// 会话模型路由不可用。
final class ComposerModelBlocker extends ComposerBlocker {
  const ComposerModelBlocker();

  @override
  bool get blocksSubmission => true;

  @override
  bool operator ==(Object other) => other is ComposerModelBlocker;

  @override
  int get hashCode => (ComposerModelBlocker).hashCode;
}

/// Studio Recovery 明确阻止该目标访问或执行。
final class ComposerRecoveryBlocker extends ComposerBlocker {
  const ComposerRecoveryBlocker(this.issue);

  final StudioRecoveryIssue issue;

  @override
  bool get blocksSubmission => true;

  @override
  bool operator ==(Object other) =>
      other is ComposerRecoveryBlocker && issue == other.issue;

  @override
  int get hashCode => Object.hash(ComposerRecoveryBlocker, issue);
}

/// 后端返回的类型化失败原因（继续、停止或提交被明确拒绝）。
final class ComposerFailureBlocker extends ComposerBlocker {
  const ComposerFailureBlocker(this.reason, {this.recoveryIssue});

  /// 后端提供的结构化原因；`null` 表示没有可识别原因，展示层用中性说明代替。
  final StudioFailureReason? reason;

  /// Recovery 拒绝的结构化 issue；UI 使用当前 locale 格式化展示。
  final StudioRecoveryIssue? recoveryIssue;

  /// 只表达「上一次操作被拒绝」，用户仍可按当前事实重试。
  @override
  bool get blocksSubmission => false;

  @override
  bool operator ==(Object other) =>
      other is ComposerFailureBlocker &&
      reason == other.reason &&
      recoveryIssue?.id == other.recoveryIssue?.id &&
      recoveryIssue?.scope == other.recoveryIssue?.scope &&
      recoveryIssue?.impact == other.recoveryIssue?.impact &&
      recoveryIssue?.projectId == other.recoveryIssue?.projectId &&
      recoveryIssue?.threadId == other.recoveryIssue?.threadId &&
      recoveryIssue?.detail == other.recoveryIssue?.detail &&
      _sameRecoveryActions(
        recoveryIssue?.availableActions,
        other.recoveryIssue?.availableActions,
      );

  @override
  int get hashCode => Object.hash(
    reason,
    recoveryIssue?.id,
    recoveryIssue?.scope,
    recoveryIssue?.impact,
    recoveryIssue?.projectId,
    recoveryIssue?.threadId,
    recoveryIssue?.detail,
    Object.hashAll(recoveryIssue?.availableActions ?? const []),
  );
}

bool _sameRecoveryActions(
  List<RecoveryIssueAction>? left,
  List<RecoveryIssueAction>? right,
) {
  if (identical(left, right)) return true;
  if (left == null || right == null || left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

/// 主按钮的完整语义状态。
final class ComposerPrimaryAction {
  const ComposerPrimaryAction({
    required this.kind,
    required this.enabled,
    this.blocker,
  });

  /// 按当前 canonical 事实推导主按钮状态。
  ///
  /// [execution] 是会话自己的执行身份（准备、等待准入、运行或清理期都存在），
  /// [continuation] 是该会话唯一继续点的只读投影。停止与继续一旦受理就必须先
  /// 显示进行中，不能等新轮次出现才更新，也不能据回执伪造运行状态。
  ///
  /// [continuationPending] 表示这次继续请求已经发出但还没有受理回执：它是“请求在途”，
  /// 不是“已受理”。这段时间既不显示进行中（回执还没到），也不允许重复提交。
  factory ComposerPrimaryAction.resolve({
    required bool isChild,
    required AgentExecutionView? execution,
    required ContinuationView? continuation,
    required bool hasContent,
    required bool submissionPending,
    required bool stopAccepted,
    required bool continuationAccepted,
    bool continuationPending = false,
    ComposerBlocker? blocker,
  }) {
    // 子会话没有用户操作：详情只读，执行由主智能体调度。
    if (isChild) {
      return const ComposerPrimaryAction(
        kind: ComposerPrimaryActionKind.readOnly,
        enabled: false,
      );
    }
    // 内容提交的准入：启用、有内容、不在提交中且没有阻塞原因。
    // 只有不可绕过的前置条件阻塞提交；上一次被拒绝的原因照常显示但允许重试。
    final blocked = blocker?.blocksSubmission ?? false;
    final requestPending = submissionPending || continuationPending;
    final submitEnabled = !requestPending && !blocked && hasContent;
    // 停止已受理但清理未结束：既不继续也不提交，且不再提供停止入口。
    if (stopAccepted || (execution?.phase.isStopping ?? false)) {
      return ComposerPrimaryAction(
        kind: ComposerPrimaryActionKind.stopping,
        enabled: false,
        blocker: blocker,
      );
    }
    if (execution != null) {
      if (hasContent) {
        return ComposerPrimaryAction(
          kind: ComposerPrimaryActionKind.sendAndContinue,
          enabled: submitEnabled,
          blocker: blocker,
        );
      }
      // 阻塞原因不隐藏停止入口：这是唯一能中断当前执行的通道。
      return ComposerPrimaryAction(
        kind: ComposerPrimaryActionKind.stop,
        enabled: true,
        blocker: blocker,
      );
    }
    if (continuationAccepted || (continuation?.claimed ?? false)) {
      return ComposerPrimaryAction(
        kind: ComposerPrimaryActionKind.continuing,
        enabled: false,
        blocker: blocker,
      );
    }
    final unclaimed = continuation != null && !continuation.claimed;
    if (unclaimed) {
      if (hasContent) {
        // 内容提交在受理时认领同一继续点，不额外创建控制输入。
        return ComposerPrimaryAction(
          kind: ComposerPrimaryActionKind.sendAndContinue,
          enabled: submitEnabled,
          blocker: blocker,
        );
      }
      return ComposerPrimaryAction(
        kind: ComposerPrimaryActionKind.continueConversation,
        enabled: !requestPending && !blocked,
        blocker: blocker,
      );
    }
    // 没有中断工作：普通发送，空输入只是禁用态，不显示继续。
    return ComposerPrimaryAction(
      kind: ComposerPrimaryActionKind.send,
      enabled: !submissionPending && !blocked && hasContent,
      blocker: blocker,
    );
  }

  final ComposerPrimaryActionKind kind;

  /// 主按钮此刻是否可点。
  final bool enabled;

  /// 可显示的阻塞原因；与 [enabled] 不同，它也可能存在于仍可停止的运行中会话。
  final ComposerBlocker? blocker;

  /// 回车是否提交。
  ///
  /// 空输入继续必须显式点击按钮，避免随手回车产生计费请求；有内容发送仍与主按钮
  /// 一致。停止、正在停止与正在继续都不由回车触发。
  bool get enterSubmits =>
      enabled &&
      (kind == ComposerPrimaryActionKind.send ||
          kind == ComposerPrimaryActionKind.sendAndContinue);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComposerPrimaryAction &&
          kind == other.kind &&
          enabled == other.enabled &&
          blocker == other.blocker;

  @override
  int get hashCode => Object.hash(kind, enabled, blocker);

  @override
  String toString() =>
      'ComposerPrimaryAction($kind, enabled: $enabled, blocker: $blocker)';
}
