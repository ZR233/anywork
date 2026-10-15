import '../../../models.dart';
import '../../../anywork_client.dart' show ReadModel;
import 'domain_sync.dart';

class PersistenceStore extends ReadModel<PersistenceStoreState> {
  PersistenceStore() : super(const PersistenceStoreState());

  void applyState(PersistenceStateSnapshot next) {
    if (state.stateLoaded && next.revision <= state.stateRevision) return;
    state = state.copyWith(
      persistence: next,
      stateLoaded: true,
      stateSync: state.stateSync.connected(),
    );
  }

  void applyQueue(PersistenceQueueStateView next) {
    if (state.queueLoaded && next.revision <= state.queueRevision) return;
    state = state.copyWith(
      queue: next,
      queueLoaded: true,
      queueSync: state.queueSync.connected(),
    );
  }

  void applyStateTransport(DomainSyncStatus sync) {
    if (sync == state.stateSync) return;
    state = state.copyWith(stateSync: sync);
  }

  void applyQueueTransport(DomainSyncStatus sync) {
    if (sync == state.queueSync) return;
    state = state.copyWith(queueSync: sync);
  }
}

class PersistenceStoreState {
  const PersistenceStoreState({
    this.persistence,
    this.stateLoaded = false,
    this.stateSync = const DomainSyncStatus(),
    this.queue,
    this.queueLoaded = false,
    this.queueSync = const DomainSyncStatus(),
  });

  final PersistenceStateSnapshot? persistence;
  final bool stateLoaded;
  final DomainSyncStatus stateSync;
  final PersistenceQueueStateView? queue;
  final bool queueLoaded;
  final DomainSyncStatus queueSync;

  int get stateRevision => persistence?.revision ?? 0;
  int get queueRevision => queue?.revision ?? 0;

  PersistenceStoreState copyWith({
    PersistenceStateSnapshot? persistence,
    bool? stateLoaded,
    DomainSyncStatus? stateSync,
    PersistenceQueueStateView? queue,
    bool? queueLoaded,
    DomainSyncStatus? queueSync,
  }) {
    return PersistenceStoreState(
      persistence: persistence ?? this.persistence,
      stateLoaded: stateLoaded ?? this.stateLoaded,
      stateSync: stateSync ?? this.stateSync,
      queue: queue ?? this.queue,
      queueLoaded: queueLoaded ?? this.queueLoaded,
      queueSync: queueSync ?? this.queueSync,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PersistenceStoreState &&
          stateLoaded == other.stateLoaded &&
          stateRevision == other.stateRevision &&
          queueLoaded == other.queueLoaded &&
          queueRevision == other.queueRevision &&
          stateSync == other.stateSync &&
          queueSync == other.queueSync &&
          identical(persistence, other.persistence) &&
          identical(queue, other.queue);

  @override
  int get hashCode => Object.hash(
    stateLoaded,
    stateRevision,
    queueLoaded,
    queueRevision,
    stateSync,
    queueSync,
    identityHashCode(persistence),
    identityHashCode(queue),
  );
}
