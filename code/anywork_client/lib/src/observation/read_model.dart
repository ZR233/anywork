import '../contracts/stamps.dart';
import 'latest_value.dart';

/// Business stores own this source; UI observers only attach to it.
abstract class ReadModel<S> {
  ReadModel(S initial) : source = LatestValue(initial);

  final LatestValue<S> source;
  S get state => source.value;
  set state(S next) => source.publish(next);
}

final class CanonicalValue<T> {
  const CanonicalValue({required this.stamp, required this.value});
  final ResourceStamp stamp;
  final T value;
}

/// A resource-local canonical mirror. Epoch changes require an explicit reset.
final class CanonicalReadModel<T> {
  CanonicalReadModel() : state = LatestValue<CanonicalValue<T>?>(null);

  final LatestValue<CanonicalValue<T>?> state;

  bool replace(ResourceStamp stamp, T value, {bool reset = false}) {
    final current = state.value;
    if (current != null) {
      if (current.stamp.resourceKey != stamp.resourceKey) {
        throw ArgumentError('A read model cannot change its resource key');
      }
      if (current.stamp.ownerEpoch != stamp.ownerEpoch) {
        if (!reset) return false;
      } else if (stamp.revision < current.stamp.revision) {
        return false;
      }
    }
    state.publish(CanonicalValue(stamp: stamp, value: value));
    return true;
  }

  bool patch({
    required ResourceStamp expected,
    required ResourceStamp next,
    required T Function(T) reduce,
  }) {
    final current = state.value;
    if (current == null || current.stamp != expected) return false;
    if (next.resourceKey != expected.resourceKey ||
        next.ownerEpoch != expected.ownerEpoch ||
        next.revision <= expected.revision) {
      throw ArgumentError('A patch must advance the same owner and resource');
    }
    state.publish(CanonicalValue(stamp: next, value: reduce(current.value)));
    return true;
  }
}
