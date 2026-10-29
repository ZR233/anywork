import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart';

import 'timeline_activity_group_models.dart';

/// 上层时间线消息无法转换为工作组成员的原因。
enum TimelineActivityRejectionReason {
  /// 条目尚未到达终态（工作组只接受已完成项）。
  nonTerminalItem,

  /// 无需在时间线展示的内部记账条目（如 `inference`、`file`）。
  ignoredNoContent,

  /// 条目属于用户消息、助手正文、轮次状态、原始记录或上下文压缩等非活动组类别。
  nonActivityKind,

  /// 工具调用属于独立展示卡片（提问回执、计划确认回执或独立大图卡片 `show_image`）。
  standaloneToolItem,

  /// 工具调用属于连续图片读取图集（`view_image`）。
  imageGalleryItem,

  /// 条目属于模型重连恢复提示。
  recoveryItem,
}

sealed class TimelineActivityConversionResult {
  const TimelineActivityConversionResult();
}

final class TimelineActivityConverted extends TimelineActivityConversionResult {
  const TimelineActivityConverted(this.message);

  final TimelineActivityGroupMessage message;
}

@immutable
final class TimelineActivityConversionRejected
    extends TimelineActivityConversionResult {
  const TimelineActivityConversionRejected({
    required this.reason,
    required this.itemId,
    required this.message,
  });

  final TimelineActivityRejectionReason reason;
  final String itemId;
  final String message;

  @override
  String toString() =>
      'TimelineActivityConversionRejected($reason, itemId: $itemId): $message';
}

/// 上层时间线载荷到工作组组件自有 `sealed` 消息类型 [TimelineActivityGroupMessage] 的转换器。
///
/// 轮次与何时开启新工作组由上层派发方决定；工作组组件自身只接受 [TimelineActivityGroupMessage]，
/// 不感知轮次或组外类型。上层在向工作组追加消息前通过本转换器完成单条转换：
/// - 若转换返回 [TimelineActivityConverted]，可将得到的 [TimelineActivityGroupMessage]
///   传给 [TimelineActivityGroupController.add]；
/// - 若转换返回 [TimelineActivityConversionRejected]，说明遇到了非工作组条目或未完成项，
///   上层据此结束当前工作组并按需开启下一段。
abstract final class TimelineActivityGroupAdapter {
  static TimelineActivityConversionResult convertItem(ConversationItem item) {
    TimelineActivityConversionRejected reject(
      TimelineActivityRejectionReason reason,
    ) => TimelineActivityConversionRejected(
      reason: reason,
      itemId: item.id,
      message: reason.name,
    );
    if (!item.terminal) {
      return reject(TimelineActivityRejectionReason.nonTerminalItem);
    }
    if (item.source is ConversationRecoverySource) {
      return reject(TimelineActivityRejectionReason.recoveryItem);
    }
    final refs = [
      for (final detail in item.details)
        if (detail.truncated)
          TimelineActivityDetailRef(itemId: item.id, field: detail.field),
    ];
    final h = item.header;
    String field(ThreadContentFieldView field) =>
        item.fieldFor(field)?.text ?? '';
    switch (item.descriptor) {
      case ConversationThinkingDescriptor(:final lifecycle):
        final summaries = [
          for (final f in item.fields)
            if (f.field is ThreadThinkingSummaryFieldView) f.text,
        ];
        return TimelineActivityConverted(
          TimelineThinkingGroupMessage(
            id: item.id,
            order: h.ordinal,
            createdAt: h.createdAt,
            completedAt: lifecycle.terminalAt ?? h.updatedAt,
            summary: summaries.lastOrNull ?? '',
            summaryChunks: summaries,
            content: [
              for (final f in item.fields)
                if (f.field is ThreadThinkingContentFieldView) f.text,
            ].join(),
            details: refs,
            error: lifecycle.failure,
            cancelled: lifecycle is CancelledThreadContentView,
          ),
        );
      case ConversationToolDescriptor(
        :final invocation,
        :final state,
        :final userInput,
        :final wait,
      ):
        if (userInput != null || invocation.name == 'show_image') {
          return reject(TimelineActivityRejectionReason.standaloneToolItem);
        }
        final output = switch (state) {
          ConversationToolSucceeded(:final output) => output,
          ConversationToolFailed(:final output) => output,
          _ => null,
        };
        if (invocation.name == 'view_image' ||
            (output?.attachments.any(
                  (a) => a.modality == AttachmentModalityView.image,
                ) ??
                false)) {
          return reject(TimelineActivityRejectionReason.imageGalleryItem);
        }
        final (outcome, ended, error) = switch (state) {
          ConversationToolSucceeded(:final completedAt) => (
            TimelineToolGroupOutcome.succeeded,
            completedAt,
            null,
          ),
          ConversationToolFailed(:final failedAt, :final failure) => (
            TimelineToolGroupOutcome.failed,
            failedAt,
            failure.message,
          ),
          ConversationToolCancelled(:final cancelledAt, :final reason) => (
            TimelineToolGroupOutcome.cancelled,
            cancelledAt,
            reason,
          ),
          ConversationToolDenied(:final deniedAt, :final reason) => (
            TimelineToolGroupOutcome.rejected,
            deniedAt,
            reason,
          ),
          ConversationToolInterrupted(:final interruptedAt, :final reason) => (
            TimelineToolGroupOutcome.interrupted,
            interruptedAt,
            reason,
          ),
          _ => throw StateError(
            'Terminal tool item has a non-terminal descriptor',
          ),
        };
        return TimelineActivityConverted(
          TimelineToolGroupMessage(
            id: item.id,
            order: h.ordinal,
            createdAt: h.createdAt,
            completedAt: ended,
            toolCallId: invocation.toolCallId,
            name: invocation.name,
            arguments: field(const ThreadToolArgumentsFieldView()),
            output: field(const ThreadToolResultFieldView()),
            outcome: outcome,
            error: error,
            wait: wait,
            details: refs,
            taskId: invocation.taskId,
            workingDirectory: invocation.workingDirectory,
            exitCode: output?.exitCode,
            attachments: output?.attachments ?? const [],
            timedOut:
                state is ConversationToolFailed &&
                state.failure.kind == ThreadToolFailureKindView.timedOut,
            outputArtifacts: [field(const ThreadToolOutputArtifactsFieldView())]
                .where((text) => text.isNotEmpty)
                .toList(),
          ),
        );
      case ConversationSkillDescriptor(:final value):
        return TimelineActivityConverted(
          TimelineSkillGroupMessage(
            id: item.id,
            order: h.ordinal,
            createdAt: h.createdAt,
            completedAt: value.activatedAt,
            skillName: value.name,
            source: value.source,
            providerId: value.providerId,
            resourceBase: value.resourceBase,
            cause: value.cause,
            details: refs,
          ),
        );
      case ConversationInferenceDescriptor() || ConversationFileDescriptor():
        return reject(TimelineActivityRejectionReason.ignoredNoContent);
      default:
        return reject(TimelineActivityRejectionReason.nonActivityKind);
    }
  }
}
