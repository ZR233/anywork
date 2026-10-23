import 'dart:async';

import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../rust/api/studio/products/feed/account_templates.dart' as wire;
import '../../../rust/api/studio/products/feed/templates_transport.dart' as native;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/close_converters.dart';
import '../shared/feed_connection.dart';
import 'identity_converters.dart';
import 'models_native_opening.dart';
import 'templates_converters.dart';

/// Mechanical forwarding only. Runtime Templates retains the sole material/
/// ACK window; this listener has no collection reducer or replacement source.
final class FrbAccountTemplatesConnection implements FeedConnection<AccountTemplatesFrame> {
  FrbAccountTemplatesConnection() {
    _connection = AdapterFeedConnection<wire.BridgeAccountTemplatesFrame, AccountTemplatesFrame>(
      resource: 'account-templates', openNativeStream: _stream, convert: _convert,
      failureFrame: _failureFrame,
      isTerminal: (frame) => frame is! AccountTemplatesData,
      identity: (_) => _identity?.feedId,
      acknowledgeNative: (sequence) async {
        final handle = await _opening.ready;
        _connection.owner.ensureOpen();
        await handle.ackThrough(deliverySequence: sequence);
      },
      requestNativeClose: () { _opening.handle?.requestClose(); },
      closeNative: () async => feedCloseReportFromBridge(await (await _opening.ready).close()),
      retryNativeClose: () async => feedCloseReportFromBridge(await (await _opening.ready).retryClose()),
      disposeNative: () => _opening.handle!.dispose(), mapFailure: bridgeFailure,
    );
    _opening.start(_connection.owner, native.openAccountTemplates, (handle) => handle.requestClose());
  }

  final _opening = ModelsNativeOpening<native.BridgeAccountTemplatesFeed>();
  late final AdapterFeedConnection<wire.BridgeAccountTemplatesFrame, AccountTemplatesFrame> _connection;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  ProductFeedIdentity _originalIdentity() {
    final handle = _opening.handle;
    if (handle == null) throw adapterProtocol('templates-feed-not-opened');
    final identity = productFeedIdentityFromBridge(handle.identity());
    if (identity.feedId.isEmpty || identity.ownerEpoch.isEmpty || identity.incarnation < 1 ||
        identity.resource != ProductResource.accountTemplates ||
        _identity != null && identity != _identity) {
      throw adapterProtocol('templates-feed-identity');
    }
    return _identity ??= identity;
  }

  Stream<wire.BridgeAccountTemplatesFrame> _stream() async* {
    final handle = await _opening.ready;
    _connection.owner.ensureOpen();
    _originalIdentity();
    yield* handle.stream();
  }

  AccountTemplatesFrame _convert(wire.BridgeAccountTemplatesFrame value) {
    final identity = _originalIdentity();
    final frame = templatesFrameFromBridge(value);
    final incoming = switch (frame) {
      AccountTemplatesData(event: AccountTemplatesBaselineEvent(:final identity)) => identity,
      AccountTemplatesResyncRequired(:final identity) => identity,
      AccountTemplatesFeedFailure(:final identity) => identity,
      AccountTemplatesClosed(:final identity) => identity,
      AccountTemplatesData(event: AccountTemplatesChangeEvent()) => null,
    };
    if (incoming != null && incoming != identity) throw adapterProtocol('templates-frame-identity');
    final stamp = switch (frame) {
      AccountTemplatesData(event: AccountTemplatesBaselineEvent(:final stamp)) => stamp,
      AccountTemplatesData(event: AccountTemplatesChangeEvent(:final stamp)) => stamp,
      _ => null,
    };
    if (stamp != null && (stamp.ownerEpoch != identity.ownerEpoch || stamp.incarnation != identity.incarnation)) {
      throw adapterProtocol('templates-frame-stamp');
    }
    return frame;
  }

  AccountTemplatesFrame _failureFrame(StudioFailure error) {
    final identity = _identity;
    // An invalid opening identity cannot supply a fabricated Failure envelope.
    // Preserve the original typed error rather than failing identity conversion again.
    if (identity == null) throw error;
    return AccountTemplatesFrame.failure(identity: identity, error: error);
  }

  @override
  Stream<AccountTemplatesFrame> get events => _connection.events;
  @override
  Future<void> ackThrough(int deliverySequence) {
    try {
      return _connection.ackThrough(deliverySequence);
    } on Object catch (error, stack) {
      Error.throwWithStackTrace(_connection.owner.failure(error, stack, source: 'ack-input'), stack);
    }
  }
  @override
  void requestClose() => _connection.requestClose();
  @override
  Future<FeedCloseReport> close() => _connection.close();
  @override
  Future<FeedCloseReport> retryClose() => _connection.retryClose();
}
