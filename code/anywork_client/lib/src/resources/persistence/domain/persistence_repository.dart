import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';

import 'persistence_state.dart';
import 'persistence_values.dart';

abstract interface class PersistenceRepository {
  ReadonlyLatestValue<PersistenceState> get state;
  ReadonlyLatestValue<PersistenceQueueState> get queue;
  Future<void> loadValue();
  Future<void> loadQueuePage({int limit = 32});
  Future<void> loadQueueLastError();
  OperationTicket<PersistenceReadTarget> retry();
  OperationTicket<PersistenceQueueSnapshot> retryThreadHistory(
    String threadId,
    int faultGeneration,
  );
  OperationTicket<PersistenceQueueSnapshot> resumeThreadHistory(
    String threadId,
    int faultGeneration,
  );
  void seal();
  Future<CloseReport> close({DateTime? deadline});
  Future<CloseReport> retryCleanup({DateTime? deadline});
}
