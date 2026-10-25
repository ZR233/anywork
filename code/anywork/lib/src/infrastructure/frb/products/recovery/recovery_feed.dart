import 'package:anywork_client/recovery_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/recovery.dart' as wire;
import '../../../../rust/api/studio/products/feed/recovery_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../recovery_converters.dart';
import '../product_native_opening.dart';

/// Observation never retries recovery or cleans a worktree implicitly.
final class FrbRecoveryConnection implements FeedConnection<RecoveryFrame> {
  FrbRecoveryConnection() {
    _connection =
        AdapterFeedConnection<wire.BridgeRecoveryFrame, RecoveryFrame>(
          resource: 'recovery',
          openNativeStream: _stream,
          convert: _convert,
          failureFrame: (error) {
            final identity = _identity;
            if (identity == null) throw error;
            return RecoveryFrame.failure(identity: identity, error: error);
          },
          isTerminal: (frame) => frame is! RecoveryData,
          identity: (_) => _feedId,
          acknowledgeNative: (sequence) async {
            final handle = await _opening.ready;
            _connection.owner.ensureOpen();
            await handle.ackThrough(deliverySequence: sequence);
          },
          requestNativeClose: () => _opening.handle?.requestClose(),
          closeNative: () => _closeNative(retry: false),
          retryNativeClose: () => _closeNative(retry: true),
          disposeNative: () => _opening.handle!.dispose(),
          mapFailure: bridgeFailure,
        );
    _opening.start(
      _connection.owner,
      native.openRecovery,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeRecoveryFeed>();
  late final AdapterFeedConnection<wire.BridgeRecoveryFrame, RecoveryFrame>
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeRecoveryFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('recovery-feed-identity');
    }
    _feedId ??= raw;
  }

  ProductFeedIdentity _originalIdentity() {
    final handle = _opening.handle!;
    _rememberRawIdentity(handle);
    final value = productFeedIdentityFromBridge(handle.identity());
    if (value.feedId != _feedId ||
        value.ownerEpoch.isEmpty ||
        value.incarnation < 1 ||
        value.resource != ProductResource.recovery ||
        _identity != null && value != _identity) {
      throw adapterProtocol('recovery-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeRecoveryFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  RecoveryFrame _convert(wire.BridgeRecoveryFrame value) {
    final identity = _originalIdentity();
    final frame = recoveryFrameFromBridge(value);
    final incoming = switch (frame) {
      RecoveryData(event: RecoveryBaselineEvent(:final identity)) => identity,
      RecoveryResyncRequired(:final identity) => identity,
      RecoveryFeedFailure(:final identity) => identity,
      RecoveryClosed(:final identity) => identity,
      RecoveryData(event: RecoveryChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('recovery-frame-identity');
    }
    final stamp = switch (frame) {
      RecoveryData(event: RecoveryBaselineEvent(:final stamp)) => stamp,
      RecoveryData(event: RecoveryChangeEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('recovery-frame-stamp');
    }
    return frame;
  }

  Future<FeedCloseReport> _closeNative({required bool retry}) async {
    final handle = await _opening.ready;
    if (_feedId == null) {
      try {
        _rememberRawIdentity(handle);
      } on Object catch (error, stack) {
        _connection.owner.failure(error, stack, source: 'close-identity');
      }
    }
    final report = feedCloseReportFromBridge(
      await (retry ? handle.retryClose() : handle.close()),
    );
    if (_feedId == null || report.feedId != _feedId) {
      throw adapterProtocol('recovery-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<RecoveryFrame> get events => _connection.events;
  @override
  Future<void> ackThrough(int deliverySequence) {
    try {
      return _connection.ackThrough(deliverySequence);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(
        _connection.owner.failure(error, stack, source: 'ack-input'),
        stack,
      );
    }
  }

  @override
  void requestClose() => _connection.requestClose();
  @override
  Future<FeedCloseReport> close() => _connection.close();
  @override
  Future<FeedCloseReport> retryClose() => _connection.retryClose();
}
