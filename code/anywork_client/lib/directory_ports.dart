/// Thread directory observation contracts shared by the SDK and adapters.
library;

import 'models.dart';
import 'lifecycle.dart';
import 'src/observation/latest_value.dart';

abstract interface class ThreadsObservationHandle implements ClientResource {
  Future<ThreadDirectoryFrame?> next();
}

abstract interface class ThreadObservationHandle implements ClientResource {
  Future<ThreadMetadataFrame?> next();
}

abstract interface class DirectoryFeedPort {
  Future<ThreadsObservationHandle> openThreadsObservation(
    DirectoryQuery query,
    DirectoryWindow window, {
    required ClientResourceId resourceId,
  });

  Future<ThreadObservationHandle> openThreadObservation(
    String threadId, {
    required ClientResourceId resourceId,
  });
}

abstract interface class DirectoryObservation<T> implements ClientLease {
  ValueObservation<DirectoryObservationState<T>> get state;
  Future<void> refresh();

  /// Revokes this demand synchronously and joins retirement if it was the last.
  Future<void> release();
}

final class DirectoryObservationState<T> {
  const DirectoryObservationState({
    this.frame,
    this.isLoading = true,
    this.error,
    this.closed = false,
  });

  final T? frame;
  final bool isLoading;
  final StudioFailure? error;
  final bool closed;
}
