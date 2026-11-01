import 'dart:async';

import 'models.dart';
import 'src/studio/thread_frames.dart';
export 'src/studio/thread_frames.dart';

abstract interface class ConversationTransport {
  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  });
}

/// The original feed's read lease; queries do not share its producer's receive/credit lock.
abstract interface class ConversationReader {
  String get threadId;
  Future<ChatBatch> loadOlder({
    required String before,
    required ReadDemand demand,
  });
  Future<ContentManifestPage> listContents({
    required String itemId,
    String? continuation,
    required ReadDemand demand,
  });
  Future<ContentWindow> readContent({
    required ContentRef reference,
    required ContentRange range,
  });
  ConversationContentWatch watchContent({
    required ContentRef reference,
    required ContentRange range,
  });
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  });
  void requestClose();
  Future<void> close();
}

/// Owns one range observation on the original reader.
///
/// Cancelling [windows] stops delivery and requests cancellation. Call [close]
/// to join the original resource; a failed join can be retried on this handle.
abstract interface class ConversationContentWatch {
  Stream<ContentWindow> get windows;
  void requestClose();
  Future<void> close();
}

abstract interface class ConversationFeed {
  String get threadId;
  String get subscriptionId;
  ConversationReader get reader;
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

final class ConversationChatEvent extends ConversationEvent {
  const ConversationChatEvent({required this.batch});
  final ChatBatch batch;
}

final class ConversationFailureEvent extends ConversationEvent {
  const ConversationFailureEvent({required this.failure});
  final StudioFailure failure;
}

final class ConversationClosedEvent extends ConversationEvent {
  const ConversationClosedEvent();
}
