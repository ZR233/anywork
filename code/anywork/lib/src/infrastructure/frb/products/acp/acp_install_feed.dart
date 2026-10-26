import 'package:anywork_client/acp_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/acp_install.dart' as wire;
import '../../../../rust/api/studio/products/feed/acp_install_transport.dart'
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
typedef _InstallWireFrame = wire.BridgeAcpInstallFrame;

/// `acpInstall` 的 wire 帧 → 领域帧。
///
/// 阶段进度只来自原生快照；适配层不累计字节、不推算剩余量，也不把
/// `baseRevision` 换成自己记录的水位。
AcpInstallEvent acpInstallEventFromBridge(wire.BridgeAcpInstallEvent event) =>
    switch (event) {
      wire.BridgeAcpInstallEvent_Baseline(
        :final identity,
        :final stamp,
        :final value,
      ) =>
        AcpInstallBaseline(
          identity: productFeedIdentityFromBridge(identity),
          stamp: productStampFromBridge(stamp),
          snapshot: acpInstallSnapshotFromBridge(value),
        ),
      wire.BridgeAcpInstallEvent_Change(
        :final stamp,
        :final baseRevision,
        :final value,
      ) =>
        AcpInstallChanged(
          stamp: productStampFromBridge(stamp),
          baseRevision: exactU64(baseRevision, 'ACP install base revision'),
          snapshot: acpInstallSnapshotFromBridge(value),
        ),
    };

AcpInstallFrame acpInstallFrameFromBridge(wire.BridgeAcpInstallFrame frame) =>
    switch (frame) {
      wire.BridgeAcpInstallFrame_Data(:final deliverySequence, :final event) =>
        AcpInstallData(
          deliverySequence: exactU64(deliverySequence, 'ACP install delivery'),
          event: acpInstallEventFromBridge(event),
        ),
      wire.BridgeAcpInstallFrame_ResyncRequired(
        :final identity,
        :final reason,
      ) =>
        AcpInstallResyncRequired(
          identity: productFeedIdentityFromBridge(identity),
          reason: productResyncFromBridge(reason),
        ),
      wire.BridgeAcpInstallFrame_Failure(:final identity, :final error) =>
        AcpInstallFeedFailure(
          identity: productFeedIdentityFromBridge(identity),
          error: bridgeFailure(error),
        ),
      wire.BridgeAcpInstallFrame_Closed(:final identity, :final reason) =>
        AcpInstallClosed(
          identity: productFeedIdentityFromBridge(identity),
          reason: productClosedFromBridge(reason),
        ),
    };

/// `acpInstall` 的原生订阅连接。
///
/// 与 `acpAuth` 完全独立：不同 feed 身份、不同 delivery 水位、不同关闭报告；共享
/// provider 资产不表示共享观察状态。
final class FrbAcpInstallConnection implements FeedConnection<AcpInstallFrame> {
  FrbAcpInstallConnection() {
    _connection = AdapterFeedConnection<_InstallWireFrame, AcpInstallFrame>(
      resource: 'acp-install',
      openNativeStream: _stream,
      convert: _convert,
      failureFrame: (error) {
        final identity = _identity;
        if (identity == null) throw error;
        return AcpInstallFeedFailure(identity: identity, error: error);
      },
      isTerminal: (frame) => frame is! AcpInstallData,
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
      native.openAcpInstall,
      _requestNativeClose,
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeAcpInstallFeed>();
  late final AdapterFeedConnection<_InstallWireFrame, AcpInstallFrame>
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _requestNativeClose(native.BridgeAcpInstallFeed handle) =>
      handle.requestClose();

  void _rememberRawIdentity(native.BridgeAcpInstallFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('acp-install-feed-identity');
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
        value.resource != ProductResource.acpInstall ||
        _identity != null && value != _identity) {
      throw adapterProtocol('acp-install-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeAcpInstallFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  AcpInstallFrame _convert(wire.BridgeAcpInstallFrame value) {
    final identity = _originalIdentity();
    final frame = acpInstallFrameFromBridge(value);
    final incoming = switch (frame) {
      AcpInstallData(event: AcpInstallBaseline(:final identity)) => identity,
      AcpInstallResyncRequired(:final identity) => identity,
      AcpInstallFeedFailure(:final identity) => identity,
      AcpInstallClosed(:final identity) => identity,
      AcpInstallData(event: AcpInstallChanged()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('acp-install-frame-identity');
    }
    final stamp = switch (frame) {
      AcpInstallData(event: AcpInstallBaseline(:final stamp)) => stamp,
      AcpInstallData(event: AcpInstallChanged(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('acp-install-frame-stamp');
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
      throw adapterProtocol('acp-install-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<AcpInstallFrame> get events => _connection.events;
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
