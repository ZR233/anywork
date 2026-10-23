import 'package:anywork_client/resources.dart';

/// Read-only rendering helpers. A previous value keeps its original identity
/// inside the canonical state and is never promoted to new-current evidence.
T? presentReadValue<T, R>(ReadValue<T, R>? value) => switch (value) {
  ReadyReadValue<T, R>(:final current) => current.value,
  LoadingReadValue<T, R>(:final previous) ||
  FailedReadValue<T, R>(:final previous) => previous?.value,
  _ => null,
};

CollectionWindow<T>? presentWindow<T>(CollectionMirror<T> mirror) => switch (mirror) {
  CurrentCollectionMirror<T>(:final window) => window,
  UnavailableCollectionMirror<T>(:final lastKnown) => lastKnown,
};

List<T> presentRows<T>(CollectionMirror<T> mirror) {
  final window = presentWindow(mirror);
  if (window == null) return const [];
  return List.unmodifiable([
    for (final reference in window.entries)
      if (presentReadValue(window.rows[reference.entry]) case final value?) value,
  ]);
}
