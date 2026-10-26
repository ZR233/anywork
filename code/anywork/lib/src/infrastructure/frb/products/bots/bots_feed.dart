import 'package:anywork_client/bots_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/bots_transport.dart'
    as native;
import '../../../../rust/api/studio/products/read/bots.dart' as bots;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../product_native_opening.dart';
import 'state_values.dart';

/// Opening does not claim the native producer. Only an actual events listener
/// reaches handle.stream; ACK and the original window remain native-owned.
final class FrbBotsConnection implements FeedConnection<BotsFrame> {
  FrbBotsConnection() {
    _connection = AdapterFeedConnection<bots.BridgeBotsFrame, BotsFrame>(
      resource: 'bots',
      openNativeStream: _stream,
      convert: _convert,
      failureFrame: (error) {
        final identity = _identity;
        if (identity == null) throw error;
        return BotsFrame.failure(identity: identity, error: error);
      },
      isTerminal: (frame) => frame is! BotsData,
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
      native.openBots,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeBotsFeed>();
  late final AdapterFeedConnection<bots.BridgeBotsFrame, BotsFrame> _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeBotsFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('bots-feed-identity');
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
        value.resource != ProductResource.bots ||
        _identity != null && value != _identity) {
      throw adapterProtocol('bots-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<bots.BridgeBotsFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  BotsFrame _convert(bots.BridgeBotsFrame value) {
    final identity = _originalIdentity();
    final frame = botsFrameFromBridge(value);
    final incoming = switch (frame) {
      BotsData(event: BotsBaseline(:final identity)) => identity,
      BotsResyncRequired(:final identity) => identity,
      BotsFeedFailure(:final identity) => identity,
      BotsClosed(:final identity) => identity,
      BotsData(event: BotsStateChangedPayload()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('bots-frame-identity');
    }
    final stamp = switch (frame) {
      BotsData(event: BotsBaseline(:final stamp)) => stamp,
      BotsData(event: BotsStateChangedPayload(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('bots-frame-stamp');
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
      throw adapterProtocol('bots-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<BotsFrame> get events => _connection.events;
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
