import 'package:anywork_client/persistence_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/persistence_queue.dart'
    as wire;
import '../../../../rust/api/studio/products/feed/persistence_queue_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../persistence_queue_converters.dart';
import '../product_native_opening.dart';

final class FrbPersistenceQueueConnection
    implements FeedConnection<PersistenceQueueFrame> {
  FrbPersistenceQueueConnection() {
    _connection =
        AdapterFeedConnection<
          wire.BridgePersistenceQueueFrame,
          PersistenceQueueFrame
        >(
          resource: 'persistence-queue',
          openNativeStream: _stream,
          convert: _convert,
          failureFrame: (error) {
            final identity = _identity;
            if (identity == null) throw error;
            return PersistenceQueueFrame.failure(
              identity: identity,
              error: error,
            );
          },
          isTerminal: (frame) => frame is! PersistenceQueueData,
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
      native.openPersistenceQueue,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgePersistenceQueueFeed>();
  late final AdapterFeedConnection<
    wire.BridgePersistenceQueueFrame,
    PersistenceQueueFrame
  >
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgePersistenceQueueFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('persistence-queue-feed-identity');
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
        value.resource != ProductResource.persistenceQueue ||
        _identity != null && value != _identity) {
      throw adapterProtocol('persistence-queue-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgePersistenceQueueFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  PersistenceQueueFrame _convert(wire.BridgePersistenceQueueFrame value) {
    final identity = _originalIdentity();
    final frame = persistenceQueueFrameFromBridge(value);
    final incoming = switch (frame) {
      PersistenceQueueData(
        event: PersistenceQueueBaselineEvent(:final identity),
      ) =>
        identity,
      PersistenceQueueResyncRequired(:final identity) => identity,
      PersistenceQueueFeedFailure(:final identity) => identity,
      PersistenceQueueClosed(:final identity) => identity,
      PersistenceQueueData(event: PersistenceQueueChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('persistence-queue-frame-identity');
    }
    final stamp = switch (frame) {
      PersistenceQueueData(
        event: PersistenceQueueBaselineEvent(:final stamp),
      ) =>
        stamp,
      PersistenceQueueData(event: PersistenceQueueChangeEvent(:final stamp)) =>
        stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('persistence-queue-frame-stamp');
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
      throw adapterProtocol('persistence-queue-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<PersistenceQueueFrame> get events => _connection.events;
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
