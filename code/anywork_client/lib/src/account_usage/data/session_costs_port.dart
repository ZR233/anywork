import '../../../resources.dart';
import '../../../resources_ports.dart' show FeedConnection;
import '../domain/session_costs_state.dart';
import 'session_costs_frames.dart';
import 'session_costs_reads.dart';

/// The two root-session cost capabilities. They are the only cost members of
/// the account-usage ports; the statistics feeds are a separate domain.
abstract interface class SessionCostsPort {
  Future<FeedConnection<SessionCostsFrame>> openSessionCosts(
    String rootThreadId,
  );
  Future<SessionCostsReadConnection> openSessionCostsRead(
    SessionCostsReadRef reference, {
    required ProductReadOrigin origin,
  });
}

abstract interface class SessionCostsReadConnection {
  Future<SessionCostsReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  Future<PurposeCostReadPage> purposes(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<RuntimeCostReadPage> amounts(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
