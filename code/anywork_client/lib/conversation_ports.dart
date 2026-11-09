import 'dart:async';

import 'models.dart';
import 'src/studio/thread_frames.dart';
export 'src/studio/thread_frames.dart';

abstract interface class ConversationTransport {
  /// Observes canonical state independently from content consumption.
  Future<ConversationStateFeed> openConversationStateFeed(String threadId);

  Future<ConversationFeed> openConversationFeed(
    String threadId, {
    required ChatScope scope,
    required ReadDemand demand,
  });
}

/// One bounded state subscription. It carries only state, failure and close
/// events; its identity, delivery sequence and ACK never belong to a content feed.
abstract interface class ConversationStateFeed {
  String get threadId;
  String get subscriptionId;
  Stream<ConversationFrame> get events;
  Future<void> acknowledge(int deliverySequence);
  void requestClose();
  Future<void> close();
}

/// The original feed's read lease; queries do not share its producer's receive/credit lock.
abstract interface class ConversationReader {
  String get threadId;
  Future<ThreadBusinessRefs> readBusinessRefs();
  Future<CompletedEntry> readCompleted({
    required String recordId,
    required ReadDemand demand,
  });
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

  /// Content-only events: Chat, Activity, Failure or Closed.
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

final class ConversationActivityEvent extends ConversationEvent {
  const ConversationActivityEvent({required this.snapshot});
  final ActivitySnapshot snapshot;
}

final class ConversationFailureEvent extends ConversationEvent {
  const ConversationFailureEvent({required this.failure});
  final StudioFailure failure;
}

final class ConversationClosedEvent extends ConversationEvent {
  const ConversationClosedEvent();
}
