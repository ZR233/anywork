import 'dart:async';

import 'models.dart';
import 'src/studio/thread_frames.dart';
export 'src/studio/thread_frames.dart';

abstract interface class ConversationTransport {
  Future<ConversationFeed> openConversationFeed(String threadId);
}

abstract interface class ConversationFeed {
  String get threadId;
  String get subscriptionId;
  Stream<ConversationFrame> get events;
  Future<void> acknowledge(int deliverySequence);
  Future<ConversationPage> page({String? before, int? limit});
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  });
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

final class ConversationFailureEvent extends ConversationEvent {
  const ConversationFailureEvent({required this.failure});
  final StudioFailure failure;
}

final class ConversationClosedEvent extends ConversationEvent {
  const ConversationClosedEvent();
}
