/// A latest snapshot, not a reliable event queue and not a publishing capability.
abstract interface class ReadonlyLatestValue<T> {
  T get value;
  int get observerCount;
  Observation watch(void Function(T) listener, {bool fireImmediately = false});
  LatestWatch<T> watchLatest(void Function(T) listener);
  Future<T> waitFor(bool Function(T) predicate);
}

/// Registration and snapshot acquisition happen synchronously in one isolate.
final class LatestWatch<T> {
  const LatestWatch({required this.value, required this.observation});

  final T value;
  final Observation observation;
}

abstract interface class Observation {
  bool get isCancelled;
  bool get isPaused;
  void pause();
  void resume();
  void cancel();
}
