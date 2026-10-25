import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/updates_ports.dart';

import '../../../../rust/api/studio/products/feed/updates.dart' as wire;
import '../../../../rust/api/studio/products/feed/updates_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../product_native_opening.dart';
import '../updates_converters.dart';

/// Uses the original two-Data native window, including baseline credit. Only
/// an actual consumer claims stream(); this connection never reads latest,
/// starts an update task, buffers a second feed or acknowledges automatically.
final class FrbUpdatesConnection implements FeedConnection<UpdatesFrame> {
  FrbUpdatesConnection() {
    _connection = AdapterFeedConnection<wire.BridgeUpdatesFrame, UpdatesFrame>(
      resource: 'updates',
      openNativeStream: _stream,
      convert: _convert,
      failureFrame: (error) {
        final identity = _identity;
        if (identity == null) throw error;
        return UpdatesFrame.failure(identity: identity, error: error);
      },
      isTerminal: (frame) => frame is! UpdatesData,
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
      native.openUpdates,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeUpdatesFeed>();
  late final AdapterFeedConnection<wire.BridgeUpdatesFrame, UpdatesFrame>
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeUpdatesFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('updates-feed-identity');
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
        value.resource != ProductResource.updates ||
        _identity != null && value != _identity) {
      throw adapterProtocol('updates-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeUpdatesFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  UpdatesFrame _convert(wire.BridgeUpdatesFrame value) {
    final identity = _originalIdentity();
    final frame = updatesFrameFromBridge(value);
    final incoming = switch (frame) {
      UpdatesData(event: UpdatesBaselineEvent(:final identity)) => identity,
      UpdatesResyncRequired(:final identity) => identity,
      UpdatesFeedFailure(:final identity) => identity,
      UpdatesClosed(:final identity) => identity,
      UpdatesData(event: UpdatesReplaceEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('updates-frame-identity');
    }
    final stamp = switch (frame) {
      UpdatesData(event: UpdatesBaselineEvent(:final stamp)) => stamp,
      UpdatesData(event: UpdatesReplaceEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('updates-frame-stamp');
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
      throw adapterProtocol('updates-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<UpdatesFrame> get events => _connection.events;
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
