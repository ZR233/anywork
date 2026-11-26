import 'dart:async';

import 'models.dart';

/// Opens one Native conversation observation with Rust-owned timeline semantics.
abstract interface class ConversationFeedPort {
  Future<ConversationFeedHandle> openConversationFeed(
    String threadId, {
    int initialLimit = 50,
  });
}

/// One feed owns its initial reset, status/meta snapshots and subsequent events.
///
/// The stream is single-subscription and retains the initial events until it is
/// listened to. Queries return Rust values without applying or regrouping them.
abstract interface class ConversationFeedHandle {
  String get threadId;
  LiveStatusSnapshot get liveStatusSnapshot;
  SessionMetaSnapshot get sessionMetaSnapshot;
  Stream<ConversationFeedEvent> get events;
  Future<TimelinePatch> loadOlder({required String cursor, int limit = 50});
  Future<List<WorkGroupMember>> loadWorkGroupMembers({
    int? afterSeq,
    int? beforeSeq,
  });
  Future<BodyWindow> readBodyWindow({
    required BodyRef reference,
    required int offset,
    required int maxBytes,
  });
  Future<SessionDetailWindow> readSessionDetail({
    required SessionDetailKind kind,
    required int offset,
    required int maxBytes,
  });

  /// Rust also emits this reset on [events]; consumers must apply it once.
  Future<TimelinePatch> resetToLatest({int limit = 50});
  void requestClose();
  Future<void> close();
}
