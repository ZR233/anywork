import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart' show CloseReport;
import '../../observation/latest_value.dart';
import 'activity_content.dart';
import 'content_state.dart';
import 'conversation_state.dart';

abstract interface class ConversationRepository {
  ConversationSession session(String threadId);
  ConversationSession? existingSession(String threadId);
  ThreadSessionState? sessionState(String threadId);
  Iterable<ThreadSessionState> get sessionStates;
  ValueObservation<String?> get visibleThreadId;
  void setVisibleThread(String? threadId);
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}

abstract interface class ConversationSession {
  String get threadId;
  ThreadSessionState get state;
  ValueObservation<ThreadSessionState> get source;
  ConversationContent get content;
  ValueObservation<CurrentActivity?> get currentActivity;
  bool get isActive;
  bool get isClosed;
  void refresh();
  Future<ThreadWorkspace> resyncRuntime();
}

sealed class ConversationContentFrame {
  const ConversationContentFrame();
}

final class ConversationBaselineFrame extends ConversationContentFrame {
  const ConversationBaselineFrame(this.baseline);
  final ConversationBaseline baseline;
}

final class ConversationCompletedBatchFrame extends ConversationContentFrame {
  const ConversationCompletedBatchFrame(this.batch);
  final ConversationBatch batch;
}

final class ConversationResetFrame extends ConversationContentFrame {
  const ConversationResetFrame(this.baseline);
  final ConversationBaseline baseline;
}

abstract interface class ConversationCompletionConsumer {
  Future<void> accept(ConversationContentFrame frame);
}

abstract interface class ConversationContent {
  String get threadId;
  ValueObservation<ChatUiState<bool>> get state;
  ValueObservation<CurrentActivity?> get currentActivity;
  bool get hasDemand;
  bool get isClosed;
  AttemptId? get currentAttemptId;
  int get ownedAttemptCount;
  Future<void> get ready;
  Observation attachConsumer(ConversationCompletionConsumer consumer);
  Future<CloseReport> joinRetired({DateTime? deadline});
  void refresh();
  ConversationQueryScope openScope({
    required String timelineEpoch,
    required int generation,
  });
}

abstract interface class ConversationQueryScope {
  int get generation;
  String get timelineEpoch;
  String get threadId;
  int get pendingQueries;
  bool get isActive;
  Future<ConversationPage> page({ConversationQueryCursor? before, int? limit});
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  });
  void retire();
  Future<CloseReport> close({DateTime? deadline});
}
