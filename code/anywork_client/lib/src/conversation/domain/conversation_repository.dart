import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart' show CloseReport;
import '../../observation/latest_value.dart';
import 'content_state.dart';
import 'conversation_state.dart';

abstract interface class ConversationRepository {
  ConversationSession session(String threadId);
  ConversationSession? existingSession(String threadId);
  ThreadSessionState? sessionState(String threadId);
  Iterable<ThreadSessionState> get sessionStates;
  ValueObservation<String?> get visibleThreadId;
  void setVisibleThread(String? threadId);
  Future<ConversationContent> openChildren({
    required String threadId,
    required String parentId,
    required ReadDemand demand,
  });
  /// Opens an independently owned member window for [reference].
  ///
  /// Its consumer, continuation and close lifecycle never replace Main state.
  Future<ConversationContent> openGroupMembers({
    required String threadId,
    required TimelineMembersRef reference,
    required ReadDemand demand,
  });
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

abstract interface class ConversationSession {
  String get threadId;
  ThreadSessionState get state;
  ValueObservation<ThreadSessionState> get source;
  ConversationContent get content;
  ValueObservation<CurrentProjection?> get current;
  bool get isActive;
  bool get isClosed;
  void refresh();
  Future<ThreadWorkspace> resyncRuntime();
}

abstract interface class ConversationBatchConsumer {
  Future<void> applyBatch(ChatBatch batch);
}

abstract interface class ConversationContent {
  String get threadId;
  ValueObservation<ChatUiState<bool>> get state;
  ValueObservation<CurrentProjection?> get current;
  bool get hasDemand;
  bool get isClosed;
  AttemptId? get currentAttemptId;
  int get ownedAttemptCount;
  Future<void> get ready;
  Observation attachConsumer(
    ConversationBatchConsumer consumer, {
    required ReadDemand demand,
  });
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> joinRetired({DateTime? deadline});
  void refresh();
  ConversationQueryScope openScope({required int generation});
}

abstract interface class ConversationQueryScope {
  int get generation;
  String get threadId;
  int get pendingQueries;
  bool get isActive;
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
  Stream<ContentWindow> watchContent({
    required ContentRef reference,
    required ContentRange range,
  });
  Future<CurrentCollectionPage> pageCurrent({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  });
  void retire();
  Future<CloseReport> close({DateTime? deadline});
}
