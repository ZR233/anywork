import '../../../models.dart';
import '../../contracts/stamps.dart';
import '../../lifecycle/resource_budget.dart' show CloseReport;
import '../../observation/latest_value.dart';
import 'conversation_state.dart';
import 'content_state.dart';
import 'page_coverage.dart';

abstract interface class ConversationRepository {
  ConversationSession session(String threadId);
  ConversationSession? existingSession(String threadId);
  ThreadSessionState? sessionState(String threadId);
  Iterable<ThreadSessionState> get sessionStates;

  /// The visible target whose mirror already exists; reading never creates it.
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
  bool get isActive;
  bool get isClosed;
  void refresh();
  Future<ThreadWorkspace> resyncRuntime();
}

/// A bounded tail and ordered delivery, never the full loaded history.
abstract interface class ConversationContent {
  String get threadId;
  ValueObservation<ChatUiState<ConversationContentFrame>> get state;
  bool get hasDemand;
  bool get isClosed;
  AttemptId? get currentAttemptId;
  int get ownedAttemptCount;
  ConversationContentFrame? get lastDeliveredFrame;
  Future<ConversationBaselineFrame> get ready;

  /// Wait for retired attempts only, without retrying or closing current demand.
  Future<CloseReport> joinRetired({DateTime? deadline});
  void refresh();
  ConversationQueryScope? openScope({
    required int generation,
    ConversationPageCoverage? coverage,
  });

  /// Reconcile caller-owned historical previews through the SDK's same reducer.
  /// These operations retain no historical body or presentation policy.
  ConversationItem mergeItem(
    ConversationItem current,
    ConversationItem incoming,
  );
  ConversationItem reduceItem(
    ConversationItem current,
    ConversationUpdateItem update,
  );
}

abstract interface class ConversationQueryScope {
  ConversationPageCoverage? get pageCoverage;
  int get generation;
  AttemptId get attemptId;
  String get threadId;
  int get pendingQueries;
  bool get isActive;
  Future<ConversationPage> page({String? before, int? limit});
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  });
  void retire();
  Future<CloseReport> close({DateTime? deadline});
}
