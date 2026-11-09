import '../../../models.dart';
import '../../../conversation_ports.dart' show DisplayMembers;
import '../../contracts/stamps.dart';
import '../../lifecycle/close_report.dart' show CloseReport;
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
  Future<ConversationContent> openRun({
    required String threadId,
    required CompletionRunRef reference,
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

abstract interface class TimelineBatchConsumer {
  Future<void> applyTimeline(TimelineBatch batch, LiveDisplayWindow live);
}

abstract interface class TimelineContent implements ConversationContent {
  ValueObservation<LiveDisplayWindow?> get live;
  Observation attachTimelineConsumer(
    TimelineBatchConsumer consumer, {
    required ReadDemand demand,
  });
  @override
  TimelineQueryScope openScope({required int generation});
}

abstract interface class TimelineQueryScope implements ConversationQueryScope {
  Future<TimelineBatch> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  });
  Future<LiveDisplayWindow> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  });
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  });
}

abstract interface class ConversationContent {
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
