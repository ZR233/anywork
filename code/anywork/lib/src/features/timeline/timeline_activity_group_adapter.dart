import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/studio_models.dart';
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
/// 工作组组件自身不接受任何组外类型；上层在向工作组追加消息前通过本转换器完成过滤与转换：
/// - 若转换返回 [TimelineActivityConverted]，可将得到的 [TimelineActivityGroupMessage]
///   传给 [TimelineActivityGroupController.tryAdd]；
/// - 若转换返回 [TimelineActivityConversionRejected]，说明遇到了非工作组条目或未完成项，
///   上层据此结束当前工作组。
abstract final class TimelineActivityGroupAdapter {
  static TimelineActivityConversionResult convertItem(
    StudioTimelineItem item, {
    bool requireTerminal = true,
  }) => convertPayload(
    TimelineMessagePayload.fromItem(item),
    requireTerminal: requireTerminal,
  );

  static TimelineActivityConversionResult convertPayload(
    TimelineMessagePayload payload, {
    bool requireTerminal = true,
  }) {
    if (requireTerminal && !payload.terminal) {
      return TimelineActivityConversionRejected(
        reason: TimelineActivityRejectionReason.nonTerminalItem,
        itemId: payload.id,
        message:
            'Item ${payload.id} is not terminal and cannot be converted into a completed activity group message.',
      );
    }
    if (payload.source is StudioTimelineRecoverySource) {
      return TimelineActivityConversionRejected(
        reason: TimelineActivityRejectionReason.recoveryItem,
        itemId: payload.id,
        message:
            'Item ${payload.id} is a recovery notice and does not belong to an activity group.',
      );
    }
    final item = payload.item;
    final state = item.state;
    if (state is ThreadInferenceItemStateView ||
        state is ThreadFileItemStateView) {
      return TimelineActivityConversionRejected(
        reason: TimelineActivityRejectionReason.ignoredNoContent,
        itemId: payload.id,
        message: 'Item ${payload.id} renders no visible timeline content.',
      );
    }
    final detailRefs = [
      for (final detail in payload.details)
        if (detail.truncated)
          TimelineActivityDetailRef(itemId: item.id, field: detail.field),
    ];
    final bodyUnavailable = payload.hasOmittedBody && detailRefs.isEmpty;
    final rolledBack =
        item.contextDisposition == ThreadContextDisposition.rolledBack;
    final completedAt = item.completedAt ?? item.updatedAt;

    switch (state) {
      case ThreadThinkingItemStateView(:final summary, :final content):
        final summaryChunks = summary
            .map((chunk) => chunk.trim())
            .where((chunk) => chunk.isNotEmpty)
            .toList(growable: false);
        final contentText = content
            .where((chunk) => chunk.trim().isNotEmpty)
            .join('\n\n');
        return TimelineActivityConverted(
          TimelineThinkingGroupMessage(
            id: item.id,
            threadId: item.threadId,
            turnId: item.turnId,
            order: item.ordinal,
            createdAt: item.createdAt,
            completedAt: completedAt,
            summary: summaryChunks.lastOrNull ?? '',
            summaryChunks: summaryChunks,
            content: contentText,
            rolledBack: rolledBack,
            details: detailRefs,
            bodyUnavailable: bodyUnavailable,
          ),
        );
      case ThreadToolItemStateView(
        :final invocation,
        :final lifecycle,
        :final userInput,
      ):
        if (userInput != null) {
          return TimelineActivityConversionRejected(
            reason: TimelineActivityRejectionReason.standaloneToolItem,
            itemId: payload.id,
            message:
                'Tool ${payload.id} carries userInput/plan confirmation and renders standalone.',
          );
        }
        final tool = item.tool;
        final attachments = tool?.attachments ?? const <ThreadAttachmentView>[];
        final hasImageAttachment = attachments.any(
          (attachment) => attachment.modality == AttachmentModalityView.image,
        );
        if (invocation.name == 'show_image' &&
            (hasImageAttachment || lifecycle is! SucceededThreadToolView)) {
          return TimelineActivityConversionRejected(
            reason: TimelineActivityRejectionReason.standaloneToolItem,
            itemId: payload.id,
            message:
                'Tool ${payload.id} (show_image) renders as a standalone image card.',
          );
        }
        if (hasImageAttachment) {
          return TimelineActivityConversionRejected(
            reason: TimelineActivityRejectionReason.imageGalleryItem,
            itemId: payload.id,
            message:
                'Tool ${payload.id} (${invocation.name}) carries image attachments and belongs to an image gallery group.',
          );
        }
        final outcome = switch (lifecycle) {
          SucceededThreadToolView() => TimelineToolGroupOutcome.succeeded,
          FailedThreadToolView() => TimelineToolGroupOutcome.failed,
          CancelledThreadToolView() ||
          CancellingThreadToolView() => TimelineToolGroupOutcome.cancelled,
          InterruptedThreadToolView() => TimelineToolGroupOutcome.interrupted,
          DeniedThreadToolView() => TimelineToolGroupOutcome.rejected,
          _ => TimelineToolGroupOutcome.succeeded,
        };
        final output = tool?.result ?? '';
        final outputArtifacts = [
          for (final artifact in tool?.outputArtifacts ?? const <Object?>[])
            artifact.toString(),
        ];
        return TimelineActivityConverted(
          TimelineToolGroupMessage(
            id: item.id,
            threadId: item.threadId,
            turnId: item.turnId,
            order: item.ordinal,
            createdAt: item.createdAt,
            completedAt: completedAt,
            toolCallId: invocation.toolCallId,
            name: invocation.name,
            arguments: invocation.arguments,
            output: output,
            outcome: outcome,
            error: item.error,
            outputArtifacts: outputArtifacts,
            wait: item.tool?.wait,
            rolledBack: rolledBack,
            details: detailRefs,
            bodyUnavailable: bodyUnavailable,
          ),
        );
      case ThreadSkillItemStateView(
        :final name,
        :final source,
        :final providerId,
        :final resourceBase,
        :final cause,
        :final activatedAt,
      ):
        return TimelineActivityConverted(
          TimelineSkillGroupMessage(
            id: item.id,
            threadId: item.threadId,
            turnId: item.turnId,
            order: item.ordinal,
            createdAt: item.createdAt,
            completedAt: activatedAt,
            skillName: name,
            source: source,
            providerId: providerId,
            resourceBase: resourceBase,
            cause: cause,
            rolledBack: rolledBack,
            details: detailRefs,
            bodyUnavailable: bodyUnavailable,
          ),
        );
      default:
        return TimelineActivityConversionRejected(
          reason: TimelineActivityRejectionReason.nonActivityKind,
          itemId: payload.id,
          message:
              'Item ${payload.id} (${item.kind.name}) is not a thinking, tool, or skill activity.',
        );
    }
  }
}
