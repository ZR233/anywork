import 'package:anywork_client/account_usage_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/feed/account_usage.dart' as wire;
import '../../../../rust/api/studio/products/feed/account_usage_transport.dart'
    as native;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../account_usage_converters.dart';
import '../identity_converters.dart';
import '../product_native_opening.dart';

/// The original native window includes baseline and owns contiguous ACKs.
/// Opening installs ownership; only a listener claims the stream.
final class FrbAccountUsageConnection
    implements FeedConnection<AccountUsageFrame> {
  FrbAccountUsageConnection() {
    _connection =
        AdapterFeedConnection<wire.BridgeAccountUsageFrame, AccountUsageFrame>(
          resource: 'account-usage',
          openNativeStream: _stream,
          convert: _convert,
          failureFrame: (error) {
            final identity = _identity;
            if (identity == null) throw error;
            return AccountUsageFrame.failure(identity: identity, error: error);
          },
          isTerminal: (frame) => frame is! AccountUsageDataFrame,
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
      native.openAccountUsage,
      (handle) => handle.requestClose(),
      attached: _rememberRawIdentity,
    );
  }

  final _opening = ProductNativeOpening<native.BridgeAccountUsageFeed>();
  late final AdapterFeedConnection<
    wire.BridgeAccountUsageFrame,
    AccountUsageFrame
  >
  _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  void _rememberRawIdentity(native.BridgeAccountUsageFeed handle) {
    final raw = handle.identity().feedId;
    if (raw.isEmpty || _feedId != null && raw != _feedId) {
      throw adapterProtocol('account-usage-feed-identity');
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
        value.resource != ProductResource.accountUsage ||
        _identity != null && value != _identity) {
      throw adapterProtocol('account-usage-feed-identity');
    }
    return _identity ??= value;
  }

  Stream<wire.BridgeAccountUsageFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  AccountUsageFrame _convert(wire.BridgeAccountUsageFrame value) {
    final identity = _originalIdentity();
    final frame = accountUsageFrameFromBridge(value);
    final incoming = switch (frame) {
      AccountUsageDataFrame(
        event: AccountUsageBaselineEvent(:final identity),
      ) =>
        identity,
      AccountUsageResyncRequired(:final identity) => identity,
      AccountUsageFeedFailure(:final identity) => identity,
      AccountUsageClosed(:final identity) => identity,
      AccountUsageDataFrame(event: AccountUsageChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) {
      throw adapterProtocol('account-usage-frame-identity');
    }
    final stamp = switch (frame) {
      AccountUsageDataFrame(event: AccountUsageBaselineEvent(:final stamp)) =>
        stamp,
      AccountUsageDataFrame(event: AccountUsageChangeEvent(:final stamp)) =>
        stamp,
      _ => null,
    };
    if (stamp != null &&
        (stamp.ownerEpoch != identity.ownerEpoch ||
            stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('account-usage-frame-stamp');
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
      throw adapterProtocol('account-usage-feed-close-identity');
    }
    return report;
  }

  @override
  Stream<AccountUsageFrame> get events => _connection.events;
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
