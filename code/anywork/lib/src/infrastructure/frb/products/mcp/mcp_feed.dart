import 'package:anywork_client/mcp_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/mcp.dart' as wire;
import '../../../../rust/api/studio/products/feed/mcp_transport.dart' as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../mcp_converters.dart';
import '../product_native_opening.dart';

/// The original native two-Data window owns delivery and contiguous ACKs.
/// Only an actual listener claims stream(); opening never consumes a baseline.
final class FrbMcpConnection implements FeedConnection<McpFrame> {
  FrbMcpConnection() {
    _connection = AdapterFeedConnection<wire.BridgeMcpFrame, McpFrame>(
      resource: 'mcp',
      openNativeStream: _stream,
      convert: _convert,
      failureFrame: (error) {
        final identity = _identity;
        if (identity == null) throw error;
        return McpFrame.failure(identity: identity, error: error);
      },
      isTerminal: (frame) => frame is! McpData,
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
      native.openMcp,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeMcpFeed>();
  late final AdapterFeedConnection<wire.BridgeMcpFrame, McpFrame> _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeMcpFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('mcp-feed-identity');
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
        value.resource != ProductResource.mcp ||
        _identity != null && value != _identity) {
      throw adapterProtocol('mcp-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeMcpFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  McpFrame _convert(wire.BridgeMcpFrame value) {
    final identity = _originalIdentity();
    final frame = mcpFrameFromBridge(value);
    final incoming = switch (frame) {
      McpData(event: McpBaselineEvent(:final identity)) => identity,
      McpResyncRequired(:final identity) => identity,
      McpFeedFailure(:final identity) => identity,
      McpClosed(:final identity) => identity,
      McpData(event: McpChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('mcp-frame-identity');
    }
    final stamp = switch (frame) {
      McpData(event: McpBaselineEvent(:final stamp)) => stamp,
      McpData(event: McpChangeEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('mcp-frame-stamp');
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
      throw adapterProtocol('mcp-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<McpFrame> get events => _connection.events;
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
