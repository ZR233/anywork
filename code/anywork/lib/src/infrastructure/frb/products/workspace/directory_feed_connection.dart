import 'package:anywork_client/resources_ports.dart';

import '../../../../rust/api/studio/products/identity.dart' as native;
import '../../../../rust/api/studio/types/chat.dart' as lifecycle;
import '../../shared/adapter_failure.dart';
import '../../shared/bridge_failure.dart';
import '../../shared/close_converters.dart';
import '../../shared/feed_connection.dart';
import '../identity_converters.dart';
import '../product_native_opening.dart';

/// Workspace identity binding only. The existing AdapterFeedConnection owns
/// listening, credit, query admission and real close/join; no directory mirror,
/// pending queue or transport is maintained here.
abstract base class FrbDirectoryFeedConnection<H, N, F>
    implements FeedConnection<F> {
  FrbDirectoryFeedConnection(
    this._kind, {
    required String resource,
    required Future<H> Function() open,
    required native.BridgeProductFeedIdentity Function(H) identity,
    required Stream<N> Function(H) stream,
    required Future<void> Function(H, BigInt) ack,
    required void Function(H) requestClose,
    required Future<lifecycle.BridgeFeedCloseReport> Function(H) close,
    required Future<lifecycle.BridgeFeedCloseReport> Function(H) retryClose,
    required void Function(H) dispose,
    required F Function(N) convert,
    required ProductFeedIdentity? Function(F) frameIdentity,
    required ProductProjectionStamp? Function(F) frameStamp,
    required F Function(ProductFeedIdentity, StudioFailure) failureFrame,
    required bool Function(F) isTerminal,
  }) : _resource = resource,
       _identityOf = identity {
    _connection = AdapterFeedConnection<N, F>(
      resource: resource,
      openNativeStream: () {
        _originalIdentity();
        return stream(_handle);
      },
      convert: (value) {
        final original = _originalIdentity();
        final frame = convert(value);
        final incoming = frameIdentity(frame);
        if (incoming != null && incoming != original) {
          throw adapterProtocol('$resource-frame-identity');
        }
        final stamp = frameStamp(frame);
        if (stamp != null &&
            (stamp.ownerEpoch != original.ownerEpoch ||
                stamp.incarnation != original.incarnation)) {
          throw adapterProtocol('$resource-frame-stamp');
        }
        return frame;
      },
      failureFrame: (error) => failureFrame(_originalIdentity(), error),
      isTerminal: isTerminal,
      identity: (_) => _feedId,
      acknowledgeNative: (sequence) async {
        final handle = await _opening.ready;
        _connection.owner.ensureOpen();
        _originalIdentity();
        await ack(handle, sequence);
      },
      requestNativeClose: () {
        if (_opening.handle case final handle?) requestClose(handle);
      },
      closeNative: () => _closeNative(close),
      retryNativeClose: () => _closeNative(retryClose),
      disposeNative: () => dispose(_handle),
      mapFailure: bridgeFailure,
    );
    _opening.start(
      _connection.owner,
      open,
      requestClose,
      attached: _rememberRawIdentity,
    );
  }

  final String _resource;
  final ProductResource _kind;
  final native.BridgeProductFeedIdentity Function(H) _identityOf;
  final _opening = ProductNativeOpening<H>();
  late final AdapterFeedConnection<N, F> _connection;
  String? _feedId;
  ProductFeedIdentity? _identity;
  Future<void> get opened => _opening.ready.then<void>((_) {});

  H get _handle {
    final handle = _opening.handle;
    if (handle == null) throw adapterProtocol('$_resource-missing-handle');
    return handle;
  }

  void _rememberRawIdentity(H handle) {
    final id = _identityOf(handle).feedId;
    if (id.isEmpty || _feedId != null && _feedId != id) {
      throw adapterProtocol('$_resource-feed-identity');
    }
    _feedId ??= id;
  }

  ProductFeedIdentity _originalIdentity() {
    final handle = _handle;
    _rememberRawIdentity(handle);
    final value = productFeedIdentityFromBridge(_identityOf(handle));
    if (value.feedId != _feedId ||
        value.ownerEpoch.isEmpty ||
        value.incarnation < 1 ||
        value.resource != _kind ||
        _identity != null && _identity != value) {
      throw adapterProtocol('$_resource-feed-identity');
    }
    return _identity ??= value;
  }

  Future<T> nativeQuery<T>(Future<T> Function(H) action) =>
      _connection.owner.query(() async {
        final handle = await _opening.ready;
        _connection.owner.ensureOpen();
        _originalIdentity();
        return action(handle);
      });

  ProductReadOrigin get originalOrigin {
    final identity = _originalIdentity();
    return ProductReadOrigin(
      ownerEpoch: identity.ownerEpoch,
      incarnation: identity.incarnation,
    );
  }

  Future<FeedCloseReport> _closeNative(
    Future<lifecycle.BridgeFeedCloseReport> Function(H) close,
  ) async {
    final handle = await _opening.ready;
    if (_feedId == null) {
      try {
        _rememberRawIdentity(handle);
      } on Object catch (error, stack) {
        _connection.owner.failure(error, stack, source: 'close-identity');
      }
    }
    final report = feedCloseReportFromBridge(await close(handle));
    if (_feedId == null || report.feedId != _feedId) {
      throw adapterProtocol('$_resource-close-identity');
    }
    return report;
  }

  @override
  Stream<F> get events => _connection.events;
  @override
  Future<void> ackThrough(int deliverySequence) =>
      _connection.ackThrough(deliverySequence);
  @override
  void requestClose() => _connection.requestClose();
  @override
  Future<FeedCloseReport> close() => _connection.close();
  @override
  Future<FeedCloseReport> retryClose() => _connection.retryClose();
}
