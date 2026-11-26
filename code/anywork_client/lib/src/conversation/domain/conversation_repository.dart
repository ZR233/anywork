import '../../../lifecycle.dart' show ClientCloseBudget;
import '../../../conversation_ports.dart';
import '../../../models.dart';
import '../../lifecycle/close_report.dart' show CloseReport;
import '../../observation/latest_value.dart';
import 'conversation_state.dart';

abstract interface class ConversationRepository
    implements ConversationFeedPort {
  ConversationSession session(String threadId);
  @override
  Future<ConversationFeedHandle> openConversationFeed(
    String threadId, {
    int initialLimit = 50,
  });
  ConversationSession? existingSession(String threadId);
  ThreadSessionState? sessionState(String threadId);
  Iterable<ThreadSessionState> get sessionStates;
  ValueObservation<String?> get visibleThreadId;
  void setVisibleThread(String? threadId);
  Future<CloseReport> close({ClientCloseBudget? budget});
  Future<CloseReport> retryCleanup({required ClientCloseBudget budget});
}

abstract interface class ConversationSession {
  String get threadId;
  ThreadSessionState get state;
  ValueObservation<ThreadSessionState> get source;
  bool get isActive;
  bool get isClosed;
  Future<SessionDetailWindow> readSessionDetail({
    required SessionDetailKind kind,
    required int offset,
    required int maxBytes,
  });
  void refresh();
  Future<ThreadWorkspace> resyncRuntime();
}
