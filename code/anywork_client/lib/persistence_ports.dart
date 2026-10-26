/// Typed Persistence transport values and the explicit Repository assembly factory.
library;

export 'persistence.dart';
export 'src/resources/persistence/data/persistence_frames.dart';
export 'src/resources/persistence/data/persistence_port.dart'
    show
        PersistencePort,
        PersistenceReadConnection,
        PersistenceQueueReadConnection;
export 'src/resources/persistence/data/persistence_reads.dart';
export 'src/resources/persistence/data/persistence_repository.dart'
    show createPersistenceRepository;
