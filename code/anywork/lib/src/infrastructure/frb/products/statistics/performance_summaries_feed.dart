import 'package:anywork_client/statistics_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/performance_summaries.dart'
    as wire;
import '../../../../rust/api/studio/products/feed/performance_summaries_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../performance_summaries_converters.dart';
import '../product_native_opening.dart';

/// No prefetch or eager baseline consumption: native owns the two-Data window.
final class FrbPerformanceSummariesConnection
    implements FeedConnection<PerformanceSummariesFrame> {
  FrbPerformanceSummariesConnection() {
    _connection =
        AdapterFeedConnection<
          wire.BridgePerformanceSummariesFrame,
          PerformanceSummariesFrame
        >(
          resource: 'performance-summaries',
          openNativeStream: _stream,
          convert: _convert,
          failureFrame: (error) {
            final identity = _identity;
            if (identity == null) throw error;
            return PerformanceSummariesFrame.failure(
              identity: identity,
              error: error,
            );
          },
          isTerminal: (frame) => frame is! PerformanceSummariesData,
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
      native.openPerformanceSummaries,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening =
      ProductNativeOpening<native.BridgePerformanceSummariesFeed>();
  late final AdapterFeedConnection<
    wire.BridgePerformanceSummariesFrame,
    PerformanceSummariesFrame
  >
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgePerformanceSummariesFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('performance-summaries-feed-identity');
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
        value.resource != ProductResource.performanceSummaries ||
        _identity != null && value != _identity) {
      throw adapterProtocol('performance-summaries-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgePerformanceSummariesFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  PerformanceSummariesFrame _convert(
    wire.BridgePerformanceSummariesFrame value,
  ) {
    final identity = _originalIdentity();
    final frame = summariesFrameFromBridge(value);
    final incoming = switch (frame) {
      PerformanceSummariesData(
        event: PerformanceSummariesBaselineEvent(:final identity),
      ) =>
        identity,
      PerformanceSummariesResyncRequired(:final identity) => identity,
      PerformanceSummariesFeedFailure(:final identity) => identity,
      PerformanceSummariesClosed(:final identity) => identity,
      PerformanceSummariesData(event: PerformanceSummariesChangeEvent()) =>
        null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('performance-summaries-frame-identity');
    }
    final stamp = switch (frame) {
      PerformanceSummariesData(
        event: PerformanceSummariesBaselineEvent(:final stamp),
      ) =>
        stamp,
      PerformanceSummariesData(
        event: PerformanceSummariesChangeEvent(:final stamp),
      ) =>
        stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('performance-summaries-frame-stamp');
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
      throw adapterProtocol('performance-summaries-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<PerformanceSummariesFrame> get events => _connection.events;
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
