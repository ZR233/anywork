import '../commands/mutation_board.dart';
import '../contracts/stamps.dart';
import 'composer_models.dart';
import 'interaction_models.dart';
import 'runtime_models.dart';
import 'studio_enums.dart';
import 'studio_state_snapshots.dart';
import 'thread_directory_models.dart';

export '../commands/mutation_board.dart'
    show CommitDisposition, CommitReceipt, EffectPoint;
export '../contracts/stamps.dart' show OperationId, ResourceStamp;

/// An acknowledgement produced at the canonical owner's commit point.
///
/// Revision equality is only an observation barrier. [disposition] describes
/// the actual command result, independently of previously delivered frames.
final class StudioCommandReceipt {
  StudioCommandReceipt({
    required this.operationId,
    required this.disposition,
    required Iterable<ResourceStamp> targets,
    required this.effect,
    required this.effective,
    required this.durable,
    this.requiresIdentityObservation = false,
  }) : targets = List.unmodifiable(targets);

  final OperationId operationId;
  final CommitDisposition disposition;
  final List<ResourceStamp> targets;
  final EffectPoint effect;
  final bool effective;
  final bool durable;
  final bool requiresIdentityObservation;

  CommitReceipt toCommitReceipt() => CommitReceipt(
    operationId: operationId,
    disposition: disposition,
    targets: targets,
    effect: effect,
    effective: effective,
    durable: durable,
    requiresIdentityObservation: requiresIdentityObservation,
  );
}

final class SettingsCommandReply {
  const SettingsCommandReply({required this.snapshot, required this.receipt});
  final SettingsStateSnapshot snapshot;
  final StudioCommandReceipt receipt;
}

final class ThreadModeCommandReply {
  const ThreadModeCommandReply({required this.receipt});
  final StudioCommandReceipt receipt;
}

final class ThreadModelRouteCommandReply {
  const ThreadModelRouteCommandReply({
    required this.runtime,
    required this.settings,
    required this.modeDefaultSaved,
    this.warning,
    required this.receipt,
  });
  final ThreadRuntimeView runtime;
  final SettingsStateSnapshot settings;
  final bool modeDefaultSaved;
  final String? warning;
  final StudioCommandReceipt receipt;
}

final class RenameThreadCommandReply {
  const RenameThreadCommandReply({required this.thread, required this.receipt});
  final StudioThread thread;
  final StudioCommandReceipt receipt;
}

final class ArchiveThreadCommandReply {
  const ArchiveThreadCommandReply({
    required this.result,
    required this.receipt,
  });
  final ArchiveThreadResult result;
  final StudioCommandReceipt receipt;
}

/// 精确停止的受理回执。
///
/// [stopped] 只说明停止请求已被接受；目标执行及其清理仍然要离开规范状态才算生效。
final class StopThreadCommandReply {
  const StopThreadCommandReply({
    required this.threadId,
    required this.executionId,
    required this.stopped,
    required this.receipt,
  });
  final String threadId;
  final String executionId;
  final bool stopped;
  final StudioCommandReceipt receipt;
}

/// 一次停止点击的**可判定**结果：调用方据此决定是否进入「正在停止」。
///
/// 停止目标仍在命令边界从规范投影冻结；界面缓存的身份只用于渲染，不作为命令目标。
/// 受理不等于已经结束：`StopRequested` 只证明请求已发出并被受理，结束仍要由规范状态确认。
sealed class ThreadStopOutcome {
  const ThreadStopOutcome({required this.threadId});

  final String threadId;

  /// 本次调用是否真的向执行器发出了停止请求。
  bool get requested => this is StopRequested;
}

/// 已发出精确停止请求，并带上本次冻结的执行身份。
final class StopRequested extends ThreadStopOutcome {
  const StopRequested({
    required super.threadId,
    required this.executionId,
    required this.operationId,
    required this.receipt,
  });

  /// 本次作为 `expectedExecutionId` 发出的执行编号。
  final String executionId;

  /// 本次停止请求的操作身份，用于和 mutation board 及状态观察对齐。
  final OperationId operationId;

  /// 受理回执；`disposition == noChange` 表示目标在受理瞬间已不再是当前执行。
  final StudioCommandReceipt receipt;
}

/// 规范状态里没有当前执行（界面视图可能滞后），因此没有发出请求。
final class StopNoExecution extends ThreadStopOutcome {
  const StopNoExecution({required super.threadId});
}

/// 本次点击已登记为该执行的**唯一排队重试**：当前在途停止结算后立即发出。
///
/// 它还没有发出请求（`requested == false`），也不代表已受理：界面应显示「请求在途」
/// 并禁用重复提交；重试真正发出后的受理/失败事实仍由命令板给出。
final class StopQueued extends ThreadStopOutcome {
  const StopQueued({required super.threadId, required this.executionId});

  /// 排队重试将要使用的执行编号（与当前在途尝试相同）。
  final String executionId;
}

/// 该成员行不具备停止资格（`canStop == false`、目录无此成员或未装载执行）。
///
/// 这不是失败，而是权限/成员事实：客户端不为它生成运行意图。
final class StopNotQualified extends ThreadStopOutcome {
  const StopNotQualified({required super.threadId});
}

/// 无内容继续的受理回执：控制输入、继续点与受理序号。
///
/// 新轮次尚未创建时没有轮次编号，此处不编造。
final class ContinueThreadCommandReply {
  const ContinueThreadCommandReply({
    required this.threadId,
    required this.inputId,
    required this.continuationId,
    required this.cursor,
    required this.receipt,
  });
  final String threadId;
  final String inputId;
  final String continuationId;
  final int cursor;
  final StudioCommandReceipt receipt;
}

/// 一次已受理继续操作的当前事实。
sealed class ContinuationOperationState {
  const ContinuationOperationState();
}

/// 已受理、尚未被模型请求消费的控制输入。
final class PendingContinuation extends ContinuationOperationState {
  const PendingContinuation();

  @override
  bool operator ==(Object other) => other is PendingContinuation;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// 控制输入已被某次模型请求消费，并接续到 [turnId]。
final class ConsumedContinuation extends ContinuationOperationState {
  const ConsumedContinuation(this.turnId);
  final String turnId;

  @override
  bool operator ==(Object other) =>
      other is ConsumedContinuation && turnId == other.turnId;

  @override
  int get hashCode => Object.hash(runtimeType, turnId);
}

/// 被新的明确授权取代而放弃的控制输入。
final class DiscardedContinuation extends ContinuationOperationState {
  const DiscardedContinuation();

  @override
  bool operator ==(Object other) => other is DiscardedContinuation;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// 继续操作的只读回查结果；查询本身不激活执行。
final class ContinuationOperationView {
  const ContinuationOperationView({
    required this.threadId,
    required this.operationId,
    required this.inputId,
    required this.continuationId,
    required this.acceptedSequence,
    required this.state,
    required this.durable,
    required this.receipt,
  });
  final String threadId;
  final String operationId;
  final String inputId;
  final String continuationId;
  final int acceptedSequence;
  final ContinuationOperationState state;
  final bool durable;
  final StudioCommandReceipt receipt;
}

/// 主会话可见的一条子任务待决交互摘要。
///
/// 它是原交互的只读投影：决定仍回到 [interactionId] 的原身份，主会话只负责转交。
final class ChildInteractionSummary {
  const ChildInteractionSummary({
    required this.childThreadId,
    required this.interactionId,
    required this.kind,
    required this.revision,
    required this.interaction,
  });
  final String childThreadId;
  final String interactionId;
  final InteractionKind kind;
  final int revision;
  final PendingInteraction interaction;
}

final class InteractionCommandReply {
  const InteractionCommandReply({
    required this.interaction,
    required this.receipt,
  });
  final PendingInteraction interaction;
  final StudioCommandReceipt receipt;
}
