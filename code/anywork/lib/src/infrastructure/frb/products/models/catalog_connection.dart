import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/model_catalog.dart' as wire;
import '../../../../rust/api/studio/products/feed/model_catalog_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../model_catalog_converters.dart';
import '../product_native_opening.dart';

/// Forwards the original Catalog window. No local source mirror, pending queue
/// or automatic ACK is introduced; only a real listener claims native.stream.
final class FrbModelCatalogConnection
    implements FeedConnection<ModelCatalogFrame> {
  FrbModelCatalogConnection() {
    _connection =
        AdapterFeedConnection<wire.BridgeModelCatalogFrame, ModelCatalogFrame>(
          resource: 'model-catalog',
          openNativeStream: _stream,
          convert: _convert,
          failureFrame: (error) {
            final identity = _identity;
            if (identity == null) throw error;
            return ModelCatalogFrame.failure(identity: identity, error: error);
          },
          isTerminal: (frame) => frame is! ModelCatalogData,
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
      native.openModelCatalog,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeModelCatalogFeed>();
  late final AdapterFeedConnection<
    wire.BridgeModelCatalogFrame,
    ModelCatalogFrame
  >
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeModelCatalogFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('model-catalog-feed-identity');
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
        value.resource != ProductResource.modelCatalog ||
        _identity != null && value != _identity) {
      throw adapterProtocol('model-catalog-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeModelCatalogFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  ModelCatalogFrame _convert(wire.BridgeModelCatalogFrame value) {
    final identity = _originalIdentity();
    final frame = modelCatalogFrameFromBridge(value);
    final incoming = switch (frame) {
      ModelCatalogData(event: ModelCatalogBaselineEvent(:final identity)) =>
        identity,
      ModelCatalogResyncRequired(:final identity) => identity,
      ModelCatalogFeedFailure(:final identity) => identity,
      ModelCatalogClosed(:final identity) => identity,
      ModelCatalogData(event: ModelCatalogChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('model-catalog-frame-identity');
    }
    final stamp = switch (frame) {
      ModelCatalogData(event: ModelCatalogBaselineEvent(:final stamp)) => stamp,
      ModelCatalogData(event: ModelCatalogChangeEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('model-catalog-frame-stamp');
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
      throw adapterProtocol('model-catalog-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<ModelCatalogFrame> get events => _connection.events;
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
