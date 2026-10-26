import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/acp_auth.dart' as wire;
import '../../../../rust/api/studio/products/feed/acp_auth_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/exact_numbers.dart';
import '../../shared/feed_connection.dart';
import '../acp/acp_converters.dart';
import '../identity_converters.dart';
import '../product_native_opening.dart';

/// 生成类型名较长，别名只用于本文件的可读性；它不是包装层，也不改变帧类型。
typedef _AuthWireFrame = wire.BridgeAcpAuthFrame;

/// `acpAuth` 的 wire 帧 → 领域帧。
///
/// 逐字段转换：feed 身份、投影戳与发布方声明的水位都来自原生帧本身，适配层不推算
/// `baseRevision`、不复用上一帧水位，也不把跨订阅的重放当作同一次观察。
AcpAuthEvent acpAuthEventFromBridge(wire.BridgeAcpAuthEvent event) =>
    switch (event) {
      wire.BridgeAcpAuthEvent_Baseline(
        :final identity,
        :final stamp,
        :final value,
      ) =>
        AcpAuthBaseline(
          identity: productFeedIdentityFromBridge(identity),
          stamp: productStampFromBridge(stamp),
          snapshot: acpAuthSnapshotFromBridge(value),
        ),
      wire.BridgeAcpAuthEvent_Change(
        :final stamp,
        :final baseRevision,
        :final value,
      ) =>
        AcpAuthChanged(
          stamp: productStampFromBridge(stamp),
          baseRevision: exactU64(baseRevision, 'ACP auth base revision'),
          snapshot: acpAuthSnapshotFromBridge(value),
        ),
    };

AcpAuthFrame acpAuthFrameFromBridge(wire.BridgeAcpAuthFrame frame) =>
    switch (frame) {
      wire.BridgeAcpAuthFrame_Data(:final deliverySequence, :final event) =>
        AcpAuthData(
          deliverySequence: exactU64(deliverySequence, 'ACP auth delivery'),
          event: acpAuthEventFromBridge(event),
        ),
      wire.BridgeAcpAuthFrame_ResyncRequired(:final identity, :final reason) =>
        AcpAuthResyncRequired(
          identity: productFeedIdentityFromBridge(identity),
          reason: productResyncFromBridge(reason),
        ),
      wire.BridgeAcpAuthFrame_Failure(:final identity, :final error) =>
        AcpAuthFeedFailure(
          identity: productFeedIdentityFromBridge(identity),
          error: bridgeFailure(error),
        ),
      wire.BridgeAcpAuthFrame_Closed(:final identity, :final reason) =>
        AcpAuthClosed(
          identity: productFeedIdentityFromBridge(identity),
          reason: productClosedFromBridge(reason),
        ),
    };

/// `acpAuth` 的原生订阅连接。
///
/// 打开时固定原生 feed 身份；只有真正的监听者才 claim `stream()`，因此构造与装配不会
/// 消耗基线。delivery 连续性与 ACK 都由原始原生窗口拥有，适配层不另建队列或计数器。
final class FrbAcpAuthConnection implements FeedConnection<AcpAuthFrame> {
  FrbAcpAuthConnection() {
    _connection = AdapterFeedConnection<_AuthWireFrame, AcpAuthFrame>(
      resource: 'acp-auth',
      openNativeStream: _stream,
      convert: _convert,
      failureFrame: (error) {
        final identity = _identity;
        if (identity == null) throw error;
        return AcpAuthFeedFailure(identity: identity, error: error);
      },
      isTerminal: (frame) => frame is! AcpAuthData,
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
      native.openAcpAuth,
      _requestNativeClose,
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeAcpAuthFeed>();
  late final AdapterFeedConnection<_AuthWireFrame, AcpAuthFrame> _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _requestNativeClose(native.BridgeAcpAuthFeed handle) =>
      handle.requestClose();

  void _rememberRawIdentity(native.BridgeAcpAuthFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('acp-auth-feed-identity');
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
        value.resource != ProductResource.acpAuth ||
        _identity != null && value != _identity) {
      throw adapterProtocol('acp-auth-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeAcpAuthFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  AcpAuthFrame _convert(wire.BridgeAcpAuthFrame value) {
    final identity = _originalIdentity();
    final frame = acpAuthFrameFromBridge(value);
    final incoming = switch (frame) {
      AcpAuthData(event: AcpAuthBaseline(:final identity)) => identity,
      AcpAuthResyncRequired(:final identity) => identity,
      AcpAuthFeedFailure(:final identity) => identity,
      AcpAuthClosed(:final identity) => identity,
      AcpAuthData(event: AcpAuthChanged()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('acp-auth-frame-identity');
    }
    final stamp = switch (frame) {
      AcpAuthData(event: AcpAuthBaseline(:final stamp)) => stamp,
      AcpAuthData(event: AcpAuthChanged(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('acp-auth-frame-stamp');
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
      throw adapterProtocol('acp-auth-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<AcpAuthFrame> get events => _connection.events;
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
