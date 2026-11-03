import 'dart:async';

import 'package:anywork_client/studio_client.dart';

/// Await a canonical publication and propagate assertion/provider failures to
/// the official test runner. No polling, timer or second state projection.
Future<void> untilObserved<T>(
  ValueObservation<T> source,
  bool Function(T) predicate,
) async {
  final done = Completer<void>();
  void inspect(T value) {
    if (done.isCompleted) return;
    try {
      if (predicate(value)) done.complete();
    } catch (error, stack) {
      done.completeError(error, stack);
    }
  }

  final registration = source.watchLatest(inspect);
  try {
    inspect(registration.value);
    await done.future;
  } finally {
    registration.observation.cancel();
  }
}
