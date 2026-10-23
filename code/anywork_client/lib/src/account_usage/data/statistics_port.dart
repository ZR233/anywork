import '../../../resources.dart';
import '../../../resources_ports.dart' show FeedConnection;
import '../domain/statistics_state.dart';
import 'statistics_frames.dart';
import 'statistics_reads.dart';

abstract interface class StatisticsPort {
  Future<FeedConnection<PerformanceSummariesFrame>> openPerformanceSummaries();
  Future<FeedConnection<PerformanceHistoryFrame>> openPerformanceHistory();
  Future<FeedConnection<SessionCostsFrame>> openSessionCosts(String rootThreadId);
  Future<PerformanceSummariesReadConnection> openPerformanceSummariesRead(PerformanceSummariesReadRef reference, {required ProductReadOrigin origin});
  Future<PerformanceHistoryReadConnection> openPerformanceHistoryRead(PerformanceHistoryReadRef reference, {required ProductReadOrigin origin});
  Future<SessionCostsReadConnection> openSessionCostsRead(SessionCostsReadRef reference, {required ProductReadOrigin origin});
  Future<PerformanceSummaryIdentityReadConnection> openSummaryIdentity(PerformanceSummaryIdentityRef reference, {required ProductReadOrigin origin});
  Future<PerformanceEffortIdentityReadConnection> openEffortIdentity(PerformanceEffortIdentityRef reference, {required ProductReadOrigin origin});
  Future<PerformanceSampleIdentityReadConnection> openSampleIdentity(PerformanceSampleIdentityRef reference, {required ProductReadOrigin origin});
}

abstract interface class PerformanceSummariesReadConnection {
  Future<PerformanceSummariesReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<PerformanceSummariesEntryPage> entries({int offset = 0, int limit = 32});
  Future<PerformanceSummariesEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupSummary(String accountId, String modelId);
  Future<PerformanceSummaryReadPage> summaries(int listId, {int offset = 0, int limit = 32});
  Future<PerformanceEffortReadPage> effortBreakdowns(int listId, {int offset = 0, int limit = 32});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class PerformanceHistoryReadConnection {
  Future<PerformanceHistoryReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<PerformanceHistoryEntryPage> entries({int offset = 0, int limit = 32});
  Future<PerformanceHistoryEntityRead> entity(ProductEntityRef reference);
  Future<PerformanceSampleReadPage> samples(int listId, {int offset = 0, int limit = 32});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class SessionCostsReadConnection {
  Future<SessionCostsReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<PurposeCostReadPage> purposes(int listId, {int offset = 0, int limit = 32});
  Future<RuntimeCostReadPage> amounts(int listId, {int offset = 0, int limit = 32});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class PerformanceSummaryIdentityReadConnection {
  Future<PerformanceSummaryIdentityRead> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class PerformanceEffortIdentityReadConnection {
  Future<PerformanceEffortIdentityRead> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class PerformanceSampleIdentityReadConnection {
  Future<PerformanceSampleIdentityRead> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
