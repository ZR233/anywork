import '../../contracts/stamps.dart';
import '../../commands/mutation_board.dart' show OperationObservationOwner;
import '../../studio/commands/command_lane.dart';

/// One application-local ordering and CAS watermark, not a settings cache.
final class SettingsWriteCoordinator {
  final CommandLane _lane = CommandLane();
  ResourceStamp? _stamp;
  String? _ownerEpoch;
  Object _ownerToken = Object();
  bool _closed = false;
  bool get isClosed => _closed;
  ResourceStamp? get stamp => _stamp;

  void adoptOwnerEpoch(String epoch) {
    if (_ownerEpoch == epoch) return;
    _ownerEpoch = epoch;
    _ownerToken = Object();
    _stamp = null;
  }

  /// Freeze at intent admission, before queueing or any other await. The token
  /// identifies this incarnation, including an old -> new -> old epoch name.
  SettingsWriteOwner captureOwner() => SettingsWriteOwner._(this, _ownerToken);

  bool isCurrentOwner(SettingsWriteOwner owner) =>
      identical(owner._coordinator, this) &&
      identical(owner._token, _ownerToken);

  void requireOwner(SettingsWriteOwner owner) {
    if (!isCurrentOwner(owner)) throw SettingsWriteOwnerChanged();
  }

  void observe(ResourceStamp stamp) {
    if (stamp.resourceKey != 'settings')
      throw ArgumentError('Expected settings stamp');
    if (_ownerEpoch != null && stamp.ownerEpoch != _ownerEpoch) return;
    final previous = _stamp;
    if (previous == null ||
        previous.ownerEpoch != stamp.ownerEpoch ||
        stamp.revision > previous.revision) {
      _stamp = stamp;
    }
  }

  Future<T> enqueue<T>(Future<T> Function() action) => _lane.enqueue(action);

  Future<int> expectedRevision(
    Future<void> Function() refresh, {
    required SettingsWriteOwner owner,
  }) async {
    requireOwner(owner);
    if (_stamp == null) await refresh();
    requireOwner(owner);
    final current = _stamp;
    if (current == null) throw StateError('Settings revision is not available');
    return current.revision;
  }

  Future<void> close() {
    _closed = true;
    _lane.seal();
    return _lane.join();
  }
}

/// Opaque coordinator-owned write identity, not a snapshot or a second lane.
final class SettingsWriteOwner implements OperationObservationOwner {
  const SettingsWriteOwner._(this._coordinator, this._token);
  final SettingsWriteCoordinator _coordinator;
  final Object _token;
  @override
  bool get isCurrent => _coordinator.isCurrentOwner(this);
}

final class SettingsWriteOwnerChanged extends StateError {
  SettingsWriteOwnerChanged()
    : super('The runtime owner changed during settings write');
}
