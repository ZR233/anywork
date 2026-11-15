import '../../../conversation_ports.dart' show TimelineReader;
import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/close_report.dart' show CloseReport;
import '../../observation/latest_value.dart';
import 'content_state.dart';
import 'conversation_state.dart';

abstract interface class ConversationRepository {
  ConversationSession session(String threadId);
  Future<TimelineReader> openTimelineReader(
    String threadId, {
    required ReadDemand demand,
  });
  ConversationSession? existingSession(String threadId);
  ThreadSessionState? sessionState(String threadId);
  Iterable<ThreadSessionState> get sessionStates;
  ValueObservation<String?> get visibleThreadId;
  void setVisibleThread(String? threadId);
  Future<ConversationContent> openRecords({
    required String threadId,
    required ChatScope scope,
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
  ValueObservation<ActivitySnapshot?> get activity;
  bool get isActive;
  bool get isClosed;
  void refresh();
  Future<ThreadWorkspace> resyncRuntime();
}

abstract interface class ConversationBatchConsumer {
  Future<void> applyBatch(ChatBatch batch);
  Future<void> applyActivity(ActivitySnapshot snapshot);
}

abstract interface class TimelineQueryScope implements ConversationQueryScope {
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  });
  Future<TailSnapshot> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  });
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  });
}

/// One bounded display-member query observation, owned by its read scope.
abstract interface class DisplayMembers {
  Future<DisplayMemberPage?> next();
  void requestClose();
  Future<void> close();
}

abstract interface class ConversationQueries {
  String get threadId;
  ConversationQueryScope openScope({required int generation});
}

abstract interface class ConversationContent implements ConversationQueries {
  String get threadId;
  ValueObservation<ChatUiState<bool>> get state;
  ValueObservation<ActivitySnapshot?> get activity;
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
