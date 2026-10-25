import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/mode_catalog.dart' as wire;
import '../../../../rust/api/studio/products/feed/mode_catalog_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../mode_catalog_converters.dart';
import '../product_native_opening.dart';

/// The original native window counts the baseline and allows two unacked Data
/// frames. Listening and contiguous-prefix ACKs use the existing transport;
/// there is no local queue, baseline read or automatic ACK here.
final class FrbModeCatalogConnection
    implements FeedConnection<ModeCatalogFrame> {
  FrbModeCatalogConnection() {
    _connection =
        AdapterFeedConnection<wire.BridgeModeCatalogFrame, ModeCatalogFrame>(
          resource: 'mode-catalog',
          openNativeStream: _stream,
          convert: _convert,
          failureFrame: (error) {
            final identity = _identity;
            if (identity == null) throw error;
            return ModeCatalogFrame.failure(identity: identity, error: error);
          },
          isTerminal: (frame) => frame is! ModeCatalogData,
          identity: (_) => _feedId,
          acknowledgeNative: (sequence) async {
            final handle = await _opening.ready;
            _connection.owner.ensureOpen();
            _originalIdentity();
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
      native.openModeCatalog,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeModeCatalogFeed>();
  late final AdapterFeedConnection<
    wire.BridgeModeCatalogFrame,
    ModeCatalogFrame
  >
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeModeCatalogFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('mode-catalog-feed-identity');
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
        value.resource != ProductResource.modeCatalog ||
        _identity != null && value != _identity) {
      throw adapterProtocol('mode-catalog-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeModeCatalogFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  ModeCatalogFrame _convert(wire.BridgeModeCatalogFrame value) {
    final identity = _originalIdentity();
    final frame = modeCatalogFrameFromBridge(value);
    final incoming = switch (frame) {
      ModeCatalogData(event: ModeCatalogBaselineEvent(:final identity)) =>
        identity,
      ModeCatalogResyncRequired(:final identity) => identity,
      ModeCatalogFeedFailure(:final identity) => identity,
      ModeCatalogClosed(:final identity) => identity,
      ModeCatalogData(event: ModeCatalogChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('mode-catalog-frame-identity');
    }
    final stamp = switch (frame) {
      ModeCatalogData(event: ModeCatalogBaselineEvent(:final stamp)) => stamp,
      ModeCatalogData(event: ModeCatalogChangeEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('mode-catalog-frame-stamp');
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
      throw adapterProtocol('mode-catalog-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<ModeCatalogFrame> get events => _connection.events;
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
