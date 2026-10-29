import 'dart:async';

import 'models.dart';
import 'src/conversation/domain/activity_content.dart';
import 'src/studio/thread_frames.dart';
export 'src/studio/thread_frames.dart';

abstract interface class ConversationTransport {
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    ConversationCompletionCursor? resumeAfter,
  });
  Future<ConversationHistoryReader> openHistoryReader(String threadId);
}

/// 独立只读 scope 的原生能力，保留同一注册 Session 的代际和读取生命周期。
abstract interface class ConversationHistoryReader {
  String get threadId;
  String get timelineEpoch;
  Future<ConversationPage> page({ConversationQueryCursor? before, int? limit});
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  });
  void requestClose();
  Future<void> close();
}

abstract interface class ConversationFeed {
  String get threadId;
  String get subscriptionId;
  Stream<ConversationFrame> get events;
  Future<void> acknowledge(int deliverySequence);
  void requestClose();
  Future<void> close();
}

final class ConversationFrame {
  const ConversationFrame({
    required this.threadId,
    required this.subscriptionId,
    required this.deliverySequence,
    required this.event,
  });
  final String threadId;
  final String subscriptionId;
  final int deliverySequence;
  final ConversationEvent event;
}

sealed class ConversationEvent {
  const ConversationEvent();
}

final class ConversationStateEvent extends ConversationEvent {
  const ConversationStateEvent({required this.frame});
  final ThreadStreamFrame frame;
}

final class ConversationBaselineEvent extends ConversationEvent {
  const ConversationBaselineEvent({required this.baseline});
  final ConversationBaseline baseline;
}

final class ConversationUpdateEvent extends ConversationEvent {
  const ConversationUpdateEvent({required this.update});
  final ConversationUpdate update;
}

final class ConversationActivityContentEvent extends ConversationEvent {
  const ConversationActivityContentEvent({required this.frame, this.completed});
  final ActivityContentFrame frame;
  final ConversationUpdate? completed;
}

final class ConversationFailureEvent extends ConversationEvent {
  const ConversationFailureEvent({required this.failure});
  final StudioFailure failure;
}

final class ConversationClosedEvent extends ConversationEvent {
  const ConversationClosedEvent();
}
