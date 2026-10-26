import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/session_costs.dart' as wire;
import '../../../../rust/api/studio/products/feed/session_costs_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../product_native_opening.dart';
import '../session_costs_converters.dart';

/// The root is frozen on native open; no later current-thread lookup is used.
final class FrbSessionCostsConnection
    implements FeedConnection<SessionCostsFrame> {
  FrbSessionCostsConnection(String rootThreadId) {
    _connection =
        AdapterFeedConnection<wire.BridgeSessionCostsFrame, SessionCostsFrame>(
          resource: 'session-costs',
          openNativeStream: _stream,
          convert: _convert,
          failureFrame: (error) {
            final identity = _identity;
            if (identity == null) throw error;
            return SessionCostsFrame.failure(identity: identity, error: error);
          },
          isTerminal: (frame) => frame is! SessionCostsData,
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
      () => native.openSessionCosts(rootThreadId: rootThreadId),
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeSessionCostsFeed>();
  late final AdapterFeedConnection<
    wire.BridgeSessionCostsFrame,
    SessionCostsFrame
  >
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeSessionCostsFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('session-costs-feed-identity');
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
        value.resource != ProductResource.sessionCosts ||
        _identity != null && value != _identity) {
      throw adapterProtocol('session-costs-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeSessionCostsFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  SessionCostsFrame _convert(wire.BridgeSessionCostsFrame value) {
    final identity = _originalIdentity();
    final frame = costsFrameFromBridge(value);
    final incoming = switch (frame) {
      SessionCostsData(event: SessionCostsBaselineEvent(:final identity)) =>
        identity,
      SessionCostsResyncRequired(:final identity) => identity,
      SessionCostsFeedFailure(:final identity) => identity,
      SessionCostsClosed(:final identity) => identity,
      SessionCostsData(event: SessionCostsReplaceEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('session-costs-frame-identity');
    }
    final stamp = switch (frame) {
      SessionCostsData(event: SessionCostsBaselineEvent(:final stamp)) => stamp,
      SessionCostsData(event: SessionCostsReplaceEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('session-costs-frame-stamp');
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
      throw adapterProtocol('session-costs-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<SessionCostsFrame> get events => _connection.events;
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
