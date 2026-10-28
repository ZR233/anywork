import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/drafts.dart' show AttachmentModality;

import 'message_payload.dart';

typedef TimelineCanonicalKey = (int, String);
typedef TimelineItemListener = void Function(
  String id,
  TimelineMessagePayload? payload,
);

enum TimelinePresentationKind { single, activity, images, imageCard, recovery }

bool payloadHasIssue(TimelineMessagePayload payload) =>
    const {'failed', 'denied', 'budgetLimited'}.contains(payload.item.status);

bool timelinePayloadIsVisible(
  TimelineMessagePayload payload,
) => switch (payload.item.state) {
  ThreadInferenceItemStateView() || ThreadFileItemStateView() => false,
  ThreadTurnItemStateView(:final state) => switch (state) {
    // Cancellation is a visible control outcome even without raw error text.
    CancelledTurn() => true,
    FailedTurn() || BudgetLimitedTurn() => state.reason?.isNotEmpty == true,
    QueuedTurn() || RunningTurn() || CompletedTurn() => false,
  },
  _ => true,
};

TimelinePresentationKind presentationKindOf(TimelineMessagePayload payload) {
  if (payload.source is StudioTimelineRecoverySource) {
    return TimelinePresentationKind.recovery;
  }
  if (_isImageCard(payload)) return TimelinePresentationKind.imageCard;
  return switch (payload.item.state) {
    ThreadThinkingItemStateView() => TimelinePresentationKind.activity,
    // 技能激活与相邻同轮思考、普通工具同属一个活动组，不单独划分组边界。
    ThreadSkillItemStateView() => TimelinePresentationKind.activity,
    ThreadToolItemStateView(:final userInput) when userInput == null =>
      payload.item.tool?.name == 'view_image' ||
              (payload.item.tool?.attachments.any(
                    (a) => a.modality == AttachmentModality.image,
                  ) ??
                  false)
          ? TimelinePresentationKind.images
          : TimelinePresentationKind.activity,
    _ => TimelinePresentationKind.single,
  };
}

/// 展示工具按工具身份独立成卡片，先于通用图片附件分类判定。
///
/// 判定只读 canonical 工具名，不看返回内容：即使回执里没有图片附件，也仍是一张
/// 可读的错误态卡片，而不是退回普通工具活动组。
bool _isImageCard(TimelineMessagePayload payload) =>
    payload.item.kind == ThreadItemKind.toolCall &&
    payload.item.tool?.name == 'show_image';

int compareTimelineKeys(TimelineCanonicalKey left, TimelineCanonicalKey right) {
  final order = left.$1.compareTo(right.$1);
  return order == 0 ? left.$2.compareTo(right.$2) : order;
}
