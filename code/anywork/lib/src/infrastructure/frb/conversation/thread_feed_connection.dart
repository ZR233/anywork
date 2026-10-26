import 'dart:async';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import '../../../rust/api/studio/conversation/identity.dart' as identity;
import '../../../rust/api/studio/types/chat.dart' as lifecycle;
import '../shared/adapter_failure.dart';
import '../shared/bridge_failure.dart';
import '../shared/close_converters.dart';
import '../shared/feed_connection.dart';
import 'identity_converters.dart';

/// Original opaque opening/identity binding shared by concrete Thread facets.
/// Forwarding, admission, ACK and close/join remain on AdapterFeedConnection's
/// single owner. This holds no domain value, pending frame or alternate queue.
abstract base class FrbThreadFeedConnection<H extends Object, N, F>
    implements FeedConnection<F> {
  FrbThreadFeedConnection({
    required String resource,
    required String diagnosticPrefix,
    required ThreadFacet facet,
    required Future<H> Function() open,
    required identity.BridgeThreadFeedIdentity Function(H) identityOf,
    required Stream<N> Function(H) openNativeStream,
    required Future<void> Function(H, BigInt) acknowledgeNative,
    required void Function(H) requestNativeClose,
    required Future<lifecycle.BridgeFeedCloseReport> Function(H) closeNative,
    required Future<lifecycle.BridgeFeedCloseReport> Function(H)
    retryNativeClose,
    required void Function(H) disposeNative,
    required F Function(N) convert,
    required this._frameIdentity,
    required this._frameStamp,
    required this._failureFrame,
    required bool Function(F) isTerminal,
  }) : _diagnosticPrefix = diagnosticPrefix,
       _facet = facet,
       _identityOf = identityOf,
       _convertFrame = convert {
    _opening.future.ignore();
    _connection = AdapterFeedConnection<N, F>(
      resource: resource,
      openNativeStream: () {
        _requireDescriptor();
        return openNativeStream(_handle!);
      },
      convert: _convert,
      failureFrame: _makeFailure,
      isTerminal: isTerminal,
      identity: (_) => _identity?.feedId,
      acknowledgeNative: (sequence) {
        _requireDescriptor();
        return acknowledgeNative(_handle!, sequence);
      },
      requestNativeClose: () {
        if (_handle case final handle?) requestNativeClose(handle);
      },
      closeNative: () => _closeNative(closeNative),
      retryNativeClose: () => _closeNative(retryNativeClose),
      disposeNative: () => disposeNative(_handle!),
      mapFailure: bridgeFailure,
    );
    final finishOpening = _connection.owner.registerOpening();
    Future<H>.sync(open)
        .then<void>(
          (handle) {
            // Ownership precedes every fallible identity/number conversion. Raw ID
            // alone can prove cleanup even when the full descriptor is unusable.
            _handle = handle;
            try {
              final raw = identityOf(handle);
              _rememberFeedId(raw.feedId);
              final source = feedIdentityFromBridge(raw);
              if (source.facet != facet) {
                throw adapterProtocol('$diagnosticPrefix-source');
              }
              // The actual native mode is authoritative, including Live requests
              // which native safely interprets as Cold for retired child owners.
              _identity = source;
            } on Object catch (error, stack) {
              _descriptorFailure = (
                failure: _connection.owner.failure(
                  error,
                  stack,
                  source: 'descriptor',
                ),
                stack: stack,
              );
            }
            if (_connection.owner.isClosing) {
              try {
                requestNativeClose(handle);
              } on Object catch (error, stack) {
                _connection.owner.failure(
                  error,
                  stack,
                  source: 'late-open-close',
                );
              }
            }
            _opening.complete(handle);
          },
          onError: (Object error, StackTrace stack) {
            _opening.completeError(
              _connection.owner.failure(error, stack, source: 'open'),
              stack,
            );
          },
        )
        .whenComplete(finishOpening)
        .ignore();
  }

  // Typed diagnostic identity is independent of the lifecycle owner's label.
  final String _diagnosticPrefix;
  final ThreadFacet _facet;
  final identity.BridgeThreadFeedIdentity Function(H) _identityOf;
  final F Function(N) _convertFrame;
  final ThreadFeedIdentity? Function(F) _frameIdentity;
  final ThreadFacetStamp? Function(F) _frameStamp;
  final F Function(ThreadFeedIdentity, StudioFailure) _failureFrame;
  final _opening = Completer<H>();
  late final AdapterFeedConnection<N, F> _connection;
  H? _handle;
  String? _feedId;
  ThreadFeedIdentity? _identity;
  ({StudioFailure failure, StackTrace stack})? _descriptorFailure;

  // Descriptor errors remain with the returned closable owner, not hidden
  // behind a permanently failed factory Future that could lose the opaque.
  Future<void> get opened => _opening.future.then<void>((_) {});

  void _rememberFeedId(String value) {
    if (value.isEmpty || _feedId != null && value != _feedId) {
      throw adapterProtocol('$_diagnosticPrefix-identity');
    }
    _feedId ??= value;
  }

  void _requireDescriptor() {
    if (_descriptorFailure case final failure?) {
      Error.throwWithStackTrace(failure.failure, failure.stack);
    }
    if (_handle == null || _identity == null) {
      throw adapterProtocol('$_diagnosticPrefix-descriptor');
    }
  }

  F _convert(N value) {
    _requireDescriptor();
    final frame = _convertFrame(value);
    final incoming = _frameIdentity(frame);
    if (incoming != null && incoming != _identity) {
      throw adapterProtocol('$_diagnosticPrefix-frame-identity');
    }
    final stamp = _frameStamp(frame);
    if (stamp != null &&
        (stamp.facet != _facet ||
            stamp.runtimeEpoch != _identity!.runtimeEpoch ||
            stamp.incarnation != _identity!.incarnation)) {
      throw adapterProtocol('$_diagnosticPrefix-stamp');
    }
    return frame;
  }

  F _makeFailure(StudioFailure failure) {
    final source = _identity;
    if (source == null) throw failure;
    return _failureFrame(source, failure);
  }

  Future<FeedCloseReport> _closeNative(
    Future<lifecycle.BridgeFeedCloseReport> Function(H) closeHandle,
  ) async {
    final handle = await _opening.future;
    if (_feedId == null) {
      try {
        _rememberFeedId(_identityOf(handle).feedId);
      } on Object catch (error, stack) {
        _connection.owner.failure(error, stack, source: 'close-identity');
      }
    }
    // Always call the real closer. Neither a descriptor error nor the absence
    // of a delivered baseline can release this native responsibility early.
    final report = feedCloseReportFromBridge(await closeHandle(handle));
    if (_feedId == null || report.feedId != _feedId) {
      throw adapterProtocol('$_diagnosticPrefix-close-identity');
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
