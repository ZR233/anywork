import 'package:anywork_client/lsp_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/lsp.dart' as wire;
import '../../../../rust/api/studio/products/feed/lsp_transport.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../lsp_converters.dart';
import '../product_native_opening.dart';

/// Opening pins the observed source; listening claims the native producer.
final class FrbLspConnection implements FeedConnection<LspFrame> {
  FrbLspConnection() {
    _connection = AdapterFeedConnection<wire.BridgeLspFrame, LspFrame>(
      resource: 'lsp',
      openNativeStream: _stream,
      convert: _convert,
      failureFrame: (error) {
        final identity = _identity;
        if (identity == null) throw error;
        return LspFrame.failure(identity: identity, error: error);
      },
      isTerminal: (frame) => frame is! LspData,
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
      native.openLsp,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeLspFeed>();
  late final AdapterFeedConnection<wire.BridgeLspFrame, LspFrame> _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeLspFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('lsp-feed-identity');
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
        value.resource != ProductResource.lsp ||
        _identity != null && value != _identity) {
      throw adapterProtocol('lsp-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeLspFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  LspFrame _convert(wire.BridgeLspFrame value) {
    final identity = _originalIdentity();
    final frame = lspFrameFromBridge(value);
    final incoming = switch (frame) {
      LspData(event: LspBaselineEvent(:final identity)) => identity,
      LspResyncRequired(:final identity) => identity,
      LspFeedFailure(:final identity) => identity,
      LspClosed(:final identity) => identity,
      LspData(event: LspChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('lsp-frame-identity');
    }
    final stamp = switch (frame) {
      LspData(event: LspBaselineEvent(:final stamp)) => stamp,
      LspData(event: LspChangeEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('lsp-frame-stamp');
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
      throw adapterProtocol('lsp-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<LspFrame> get events => _connection.events;
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
