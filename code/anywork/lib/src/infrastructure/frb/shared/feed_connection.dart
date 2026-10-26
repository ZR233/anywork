import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import 'adapter_failure.dart';
import 'exact_numbers.dart';
import 'late_claim_stream.dart';
import 'resource_owner.dart';

/// Shared resource mechanics only. N and T are a single concrete domain's
/// native/domain frame pair; no runtime discriminator or business payload bus.
final class AdapterFeedConnection<N, T> implements FeedConnection<T> {
  AdapterFeedConnection({
    required String resource,
    required this._openNativeStream,
    required this._convert,
    required this._failureFrame,
    required this._isTerminal,
    required this._acknowledgeNative,
    required void Function() requestNativeClose,
    required Future<FeedCloseReport> Function() closeNative,
    required Future<FeedCloseReport> Function() retryNativeClose,
    required void Function() disposeNative,
    required StudioFailure Function(Object) mapFailure,
    this._identity,
  }) : _resource = resource {
    owner = AdapterResourceOwner(
      resource: resource,
      requestNativeClose: requestNativeClose,
      closeNative: closeNative,
      retryNativeClose: retryNativeClose,
      disposeNative: disposeNative,
      cancelNativeStream: _cancelNativeStream,
      mapFailure: mapFailure,
      expectedIdentity: () => _deliveredIdentity,
    );
  }

  final String _resource;
  final Stream<N> Function() _openNativeStream;
  final T Function(N) _convert;
  final T Function(StudioFailure) _failureFrame;
  final bool Function(T) _isTerminal;
  final Future<void> Function(BigInt) _acknowledgeNative;
  final String? Function(T)? _identity;
  late final AdapterResourceOwner owner;
  StreamSubscription<N>? _native;
  StreamController<T>? _controller;
  final Completer<void> _openingSettled = Completer<void>();
  bool _claimed = false;
  bool _terminal = false;
  String? _deliveredIdentity;

  @override
  Stream<T> get events {
    owner.ensureOpen();
    return LateClaimStream<T>(_listen);
  }

  StreamSubscription<T> _listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    owner.ensureOpen();
    if (_claimed) {
      throw StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'The $_resource stream already has a consumer',
        retryable: false,
        correlationId: 'adapter-$_resource-listen-conflict',
      );
    }
    _claimed = true;
    final finishOpening = owner.registerOpening();
    final controller = StreamController<T>();
    _controller = controller;
    controller.onCancel = () {
      // This only detaches the output observation. The same owner's original
      // close/retryClose still reports native join, raw forwarding cancellation
      // and query responsibilities, including every unresolved issue.
      requestClose();
      return owner.cancelOutputObservation();
    };
    late StreamSubscription<T> subscription;
    try {
      subscription = controller.stream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    } on Object catch (error, stack) {
      _openingSettled.complete();
      finishOpening();
      requestClose();
      Error.throwWithStackTrace(owner.failure(error, stack), stack);
    }
    scheduleMicrotask(() {
      try {
        if (!owner.isClosing) {
          _native = _openNativeStream().listen(
            _onFrame,
            onError: (Object error, StackTrace stack) => _fail(error, stack),
            onDone: () {
              if (!_terminal && !owner.isClosing) {
                _fail(
                  adapterProtocol('$_resource-stream-eof'),
                  StackTrace.current,
                );
              }
            },
          );
        }
      } on Object catch (error, stack) {
        _fail(error, stack);
      } finally {
        _openingSettled.complete();
        finishOpening();
      }
    });
    return subscription;
  }

  void _onFrame(N native) {
    if (_terminal || owner.isClosing) return;
    try {
      final frame = _convert(native);
      final identity = _identity?.call(frame);
      if (identity != null) {
        if (identity.isEmpty ||
            _deliveredIdentity != null && identity != _deliveredIdentity) {
          throw adapterProtocol('$_resource-stream-identity');
        }
        _deliveredIdentity = identity;
      }
      _controller!.add(frame);
      if (_isTerminal(frame)) {
        _terminal = true;
        requestClose();
      }
    } on Object catch (error, stack) {
      _fail(error, stack);
    }
  }

  void _fail(Object error, StackTrace stack) {
    if (_terminal || owner.isClosing) return;
    _terminal = true;
    final failure = owner.failure(error, stack);
    try {
      _controller!.add(_failureFrame(failure));
    } on Object catch (conversionError, conversionStack) {
      _controller!.addError(
        owner.failure(conversionError, conversionStack),
        conversionStack,
      );
    } finally {
      requestClose();
    }
  }

  Future<void> _cancelNativeStream() async {
    if (_claimed) await _openingSettled.future;
    await _native?.cancel();
  }

  @override
  Future<void> ackThrough(int deliverySequence) {
    owner.ensureOpen();
    final sequence = nativeU64(deliverySequence, 'delivery sequence');
    return owner.query(() => _acknowledgeNative(sequence));
  }

  @override
  void requestClose() {
    owner.requestClose();
    _terminal = true;
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      // Output onCancel observes close; close must not wait for its own callback.
      unawaited(
        controller.close().then<void>(
          (_) {},
          onError: (Object error, StackTrace stack) {
            owner.failure(error, stack);
          },
        ),
      );
    }
  }

  @override
  Future<FeedCloseReport> close() {
    requestClose();
    return owner.close();
  }

  @override
  Future<FeedCloseReport> retryClose() {
    requestClose();
    return owner.retryClose();
  }
}
