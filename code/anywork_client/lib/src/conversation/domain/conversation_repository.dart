import '../../../lifecycle.dart' show ClientCloseBudget;
import '../../../conversation_ports.dart';
import '../../../models.dart';
import '../../lifecycle/close_report.dart' show CloseReport;
import '../../observation/latest_value.dart';
import 'conversation_state.dart';

abstract interface class ConversationRepository {
  ConversationSession session(String threadId);
  Future<HistoryReader> openHistoryReader(String threadId);
  Future<CurrentReader> openCurrentReader(
    String threadId, {
    required ReadDemand demand,
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
  void refresh();
  Future<ThreadWorkspace> resyncRuntime();
}

/// Pure immutable-history queries. Results are pages, never an implicit UI apply.
abstract interface class HistoryQueryScope {
  Future<HistoryCut> capture();
  Future<HistoryTimelinePage> timelinePage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  });
  Future<HistoryGroupPage> groupPage({
    required String groupId,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  });
  Future<HistoryTimelinePage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  });
  Future<HistoryEventDetail> readEvent({
    required String eventId,
    required HistoryDemand demand,
  });
  Future<HistoryBodyPage> listBodies({
    required String eventId,
    String? cursor,
    required HistoryDemand demand,
  });
  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  });
  void retire();
  Future<CloseReport> close({ClientCloseBudget? budget});
}

/// One current-owner read scope. Metadata/body watches are independent resources.
abstract interface class CurrentQueryScope {
  String get threadId;
  int get generation;
  CurrentReader get reader;
  Future<CurrentCollectionPage> pageCollection({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  });
  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
    required ContentRange range,
  });
  CurrentBodyWatch watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  });
  void retire();
  Future<CloseReport> close({ClientCloseBudget? budget});
}
