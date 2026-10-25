import 'package:anywork_client/resources_ports.dart';

import '../domain/persistence_state.dart';
import '../domain/persistence_values.dart';
import 'persistence_frames.dart';
import 'persistence_reads.dart';

abstract interface class PersistencePort {
  Future<FeedConnection<PersistenceFrame>> openPersistence();
  Future<FeedConnection<PersistenceQueueFrame>> openPersistenceQueue();
  Future<PersistenceReadConnection> openPersistenceRead(
    PersistenceReadRef reference, {
    required ProductReadOrigin origin,
  });
  Future<PersistenceQueueReadConnection> openPersistenceQueueRead(
    PersistenceQueueReadRef reference, {
    required ProductReadOrigin origin,
  });
  Future<PersistenceReadTarget> retry();
  Future<PersistenceQueueSnapshot> retryThreadHistory(
    String threadId,
    int faultGeneration,
  );
  Future<PersistenceQueueSnapshot> resumeThreadHistory(
    String threadId,
    int faultGeneration,
  );
}

abstract interface class PersistenceReadConnection {
  Future<PersistenceReadHeader> header();
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}

abstract interface class PersistenceQueueReadConnection {
  Future<PersistenceQueueReadHeader> header();
  Future<PersistenceQueueEntryPage> entries({int offset = 0, int limit = 32});
  Future<PersistenceQueueEntityRead> entity(ProductEntityRef reference);
  Future<ProductEntityRef?> lookupThread(String threadId);
  Future<ThreadPersistenceReadPage> threads(
    int listId, {
    int offset = 0,
    int limit = 32,
  });
  Future<TextChunk> text(int fieldId, {int offset = 0, int maxBytes = 65536});
  void requestClose();
  Future<FeedCloseReport> close();
  Future<FeedCloseReport> retryClose();
}
