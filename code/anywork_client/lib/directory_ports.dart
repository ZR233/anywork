/// Thread directory observation contracts shared by the SDK and adapters.
library;

import 'models.dart';
import 'src/observation/latest_value.dart';

abstract interface class ThreadsObservationHandle {
  Future<ThreadDirectoryFrame?> next();
  void requestClose();
  Future<void> close();
}

abstract interface class ThreadObservationHandle {
  Future<ThreadMetadataFrame?> next();
  void requestClose();
  Future<void> close();
}

abstract interface class DirectoryFeedPort {
  Future<ThreadsObservationHandle> openThreadsObservation(
    DirectoryQuery query,
    DirectoryWindow window,
  );

  Future<ThreadObservationHandle> openThreadObservation(String threadId);
}

abstract interface class DirectoryObservation<T> {
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
