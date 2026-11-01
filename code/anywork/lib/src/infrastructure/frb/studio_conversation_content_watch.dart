part of 'studio_api.dart';

/// Demand-driven native window observation. There is one next Future in flight,
/// no polling, no feed ACK, and cancellation wakes that exact native wait.
final class _FrbContentWatch implements ConversationContentWatch {
  _FrbContentWatch(this.feed, this.reference, this.range) {
    feed._contentWatches.add(this);
    output = StreamController<ContentWindow>(
      onListen: _start,
      onPause: () => paused = true,
      onResume: () {
        paused = false;
        _pump();
      },
      // Cancellation seals delivery and wakes next; explicit close owns the
      // retryable native join, not Dart's potentially cached cancel Future.
      onCancel: requestClose,
    );
  }

  final FrbConversationFeed feed;
  final ContentRef reference;
  final ContentRange range;
  late final StreamController<ContentWindow> output;
  Future<void>? opening;
  Future<void>? draining;
  Future<void>? closingNative;
  String? watchId;
  bool cancelled = false;
  bool paused = false;
  bool ended = false;
  bool nativeClosed = false;
  bool outputEnded = false;
  Object? closeError;
  StackTrace? closeStack;
  Future<void>? closing;

  @override
  Stream<ContentWindow> get windows => output.stream;

  void _start() {
    if (cancelled || feed._admissionsClosed) {
      if (!cancelled) output.addError(_conversationClosedFailure);
      feed._contentWatches.remove(this);
      _endOutput();
      return;
    }
    final completion = Completer<void>();
    opening = completion.future;
    completion.complete(
      Future<void>.sync(() async {
        try {
          final id = await feed._native.openContentWatch(
            reference: _contentRefToFrb(reference),
            range: frb_chat_types.BridgeContentRange(
              offset: BigInt.from(range.offset),
              maxBytes: range.maxBytes,
            ),
          );
          watchId = id;
          if (cancelled || feed._admissionsClosed) {
            requestClose();
          } else {
            _pump();
          }
        } catch (error, stack) {
          if (!cancelled) output.addError(_studioFailure(error), stack);
          if (watchId == null) feed._contentWatches.remove(this);
          _endOutput();
        }
      }),
    );
  }

  void _pump() {
    if (cancelled || ended || paused || draining != null || watchId == null) {
      return;
    }
    final completion = Completer<void>();
    draining = completion.future;
    completion.complete(
      Future<void>.sync(() async {
        try {
          while (!cancelled && !ended && !paused) {
            final value = await feed._native.nextContentWindow(
              watchId: watchId!,
            );
            if (cancelled) break;
            if (value == null) {
              ended = true;
              _endOutput();
              break;
            }
            output.add(_contentWindowFromFrb(value));
            // Let a consumer pause in this delivery before claiming a successor.
            await Future<void>.value();
          }
        } catch (error, stack) {
          if (!cancelled) output.addError(_studioFailure(error), stack);
          requestClose();
          _endOutput();
        } finally {
          draining = null;
        }
      }),
    );
  }

  @override
  void requestClose() {
    cancelled = true;
    final id = watchId;
    if (id == null || nativeClosed) return;
    try {
      feed._native.requestCloseContentWatch(watchId: id);
    } catch (error, stack) {
      closeError = error;
      closeStack = stack;
    }
  }

  Future<void> _joinNative() {
    if (nativeClosed || watchId == null) return Future.value();
    final existing = closingNative;
    if (existing != null) return existing;
    final completion = Completer<void>();
    closingNative = completion.future;
    completion.complete(
      Future<void>.sync(() async {
        try {
          await feed._native.closeContentWatch(watchId: watchId!);
          nativeClosed = true;
          closeError = null;
          feed._contentWatches.remove(this);
        } catch (error, stack) {
          closeError = error;
          closeStack = stack;
          rethrow;
        } finally {
          closingNative = null;
        }
      }),
    );
    return completion.future;
  }

  @override
  Future<void> close() {
    // This part executes synchronously before awaiting open/next/join.
    requestClose();
    final existing = closing;
    if (existing != null) return existing;
    final completion = Completer<void>();
    closing = completion.future;
    completion.complete(_close().whenComplete(() => closing = null));
    return completion.future;
  }

  Future<void> _close() async {
    await opening;
    requestClose(); // Covers a watch id published by a late successful open.
    Object? failure;
    StackTrace? failureStack;
    try {
      await _joinNative();
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    // A failed native join cannot skip the original in-flight next.
    try {
      await draining;
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
    if (failure != null) {
      Error.throwWithStackTrace(_studioFailure(failure), failureStack!);
    }
    if (closeError case final error?) {
      Error.throwWithStackTrace(
        _studioFailure(error),
        closeStack ?? StackTrace.current,
      );
    }
    _endOutput();
    if (watchId == null) feed._contentWatches.remove(this);
  }

  void _endOutput() {
    outputEnded = true;
    unawaited(output.close());
  }
}
