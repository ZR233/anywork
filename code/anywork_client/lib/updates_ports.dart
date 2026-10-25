/// Typed update preparation-task capabilities; no application exit coordinator.
library;

export 'updates.dart';
export 'src/updates/data/updates_lifecycle.dart' show UpdatesLifecycle;
export 'src/updates/data/update_task.dart';
export 'src/updates/data/updates_frames.dart';
export 'src/updates/data/updates_reads.dart';
export 'src/updates/data/updates_port.dart';
export 'src/updates/data/updates_repository.dart' show createUpdatesRepository;
