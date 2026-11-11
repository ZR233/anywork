part of 'studio_api.dart';

/// Mechanical typed transport only. The SDK owns continuity, reduction and ACK.
final class FrbConversationFeed extends _FrbConversationDelivery
    implements ConversationFeed {
  FrbConversationFeed(frb_chat.BridgeConversationFeed native)
    : this._(_FrbNativeConversation.conversation(native));

  FrbConversationFeed._(this._native)
    : super(_native.threadId(), _native.subscriptionId());

  final _FrbNativeConversation _native;
  @override
  late final ConversationReader reader = _FrbConversationReader(this);
  final Set<_FrbContentWatch> _contentWatches = {};
  final Set<_FrbDisplayMembers> _memberWatches = {};
  @override
  Stream<frb_chat_types.BridgeConversationFrame> _nativeEvents() =>
      _native.events();
  @override
  void _nativeAcknowledge(int sequence) => _native.acknowledge(
    subscriptionId: subscriptionId,
    deliverySequence: BigInt.from(sequence),
  );
  @override
  void _nativeRequestClose() => _native.requestClose();
  @override
  Future<void> _nativeClose() => _native.close();
  @override
  void _nativeDispose() => _native.dispose();
  @override
  void _requestCloseChildren() {
    for (final watch in List.of(_contentWatches)) {
      watch.requestClose();
    }
    for (final watch in List.of(_memberWatches)) {
      watch.requestClose();
    }
  }

  @override
  Iterable<Future<void>> _closeChildren() => [
    for (final watch in List.of(_contentWatches)) watch.close(),
    for (final watch in List.of(_memberWatches)) watch.close(),
  ];
}

final class FrbConversationStateFeed extends _FrbConversationDelivery
    implements ConversationStateFeed {
  FrbConversationStateFeed(this._native)
    : super(_native.threadId(), _native.subscriptionId());

  final frb_chat.BridgeConversationStateFeed _native;
  @override
  Stream<frb_chat_types.BridgeConversationFrame> _nativeEvents() =>
      _native.events();
  @override
  void _nativeAcknowledge(int sequence) => _native.acknowledge(
    subscriptionId: subscriptionId,
    deliverySequence: BigInt.from(sequence),
  );
  @override
  void _nativeRequestClose() => _native.requestClose();
  @override
  Future<void> _nativeClose() => _native.close();
  @override
  void _nativeDispose() => _native.dispose();
}

/// Shared transport lifetime only; no domain state or recovery is reduced here.
abstract class _FrbConversationDelivery {
  _FrbConversationDelivery(this.threadId, this.subscriptionId);

  Stream<frb_chat_types.BridgeConversationFrame> _nativeEvents();
  void _nativeAcknowledge(int sequence);
  void _nativeRequestClose();
  Future<void> _nativeClose();
  void _nativeDispose();
  void _requestCloseChildren() {}
  Iterable<Future<void>> _closeChildren() => const [];

  final String threadId;
  final String subscriptionId;
  _DartSubscription? _registration;
  bool get _admissionsClosed =>
      _closed || (_registration?.cancelRequested ?? false);
  bool _closed = false;
  bool _eventsEnded = false;
  bool _listened = false;
  bool _disposed = false;
  Future<void>? _closing;
  Future<void>? _nativeClosing;
  StreamSubscription<frb_chat_types.BridgeConversationFrame>? _subscription;
  late final StreamController<ConversationFrame> _controller = StreamController(
    onListen: _listen,
    onCancel: () {
      if (_eventsEnded) return Future<void>.value();
      // Synchronous native cancellation, including idle/credit waits.
      requestClose();
      return close();
    },
  );

  Stream<ConversationFrame> get events {
    if (_admissionsClosed) throw _conversationClosedFailure;
    if (_listened) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'Conversation events already have a consumer',
        retryable: false,
        correlationId: 'client-conversation-consumer',
      );
    }
    _listened = true;
    return _controller.stream;
  }

  void _listen() {
    if (_admissionsClosed) {
      unawaited(_controller.close());
      return;
    }
    try {
      _subscription = _nativeEvents().listen(
        (value) {
          if (_admissionsClosed) return;
          try {
            _controller.add(
              ConversationFrame(
                threadId: value.threadId,
                subscriptionId: value.subscriptionId,
                deliverySequence: _exactTimelineInt(
                  value.deliverySequence,
                  'delivery sequence',
                ),
                event: switch (value.event) {
                  frb_chat_types.BridgeConversationEvent_State(:final update) =>
                    ConversationStateEvent(
                      frame: _threadStreamFrameFromFrb(update),
                    ),
                  frb_chat_types.BridgeConversationEvent_Chat(:final batch) =>
                    ConversationChatEvent(batch: _chatBatchFromFrb(batch)),
                  frb_chat_types.BridgeConversationEvent_Timeline(
                    :final batch,
                  ) =>
                    ConversationTimelineEvent(
                      batch: _timelineBatchFromFrb(batch),
                    ),
                  frb_chat_types.BridgeConversationEvent_Activity(
                    :final snapshot,
                  ) =>
                    ConversationActivityEvent(
                      snapshot: _activitySnapshotFromFrb(snapshot),
                    ),
                  frb_chat_types.BridgeConversationEvent_Failure(
                    :final error,
                  ) =>
                    ConversationFailureEvent(
                      failure: _studioFailure(error) as StudioFailure,
                    ),
                  frb_chat_types.BridgeConversationEvent_Closed() =>
                    const ConversationClosedEvent(),
                },
              ),
            );
          } catch (error, stack) {
            _conversionFailed(error, stack);
          }
        },
        onError: _conversionFailed,
        onDone: () {
          _eventsEnded = true;
          unawaited(_controller.close());
        },
      );
    } catch (error, stack) {
      _conversionFailed(error, stack);
    }
  }

  void _conversionFailed(Object error, StackTrace stack) {
    if (_closed) return;
    requestClose();
    _controller.addError(_studioFailure(error), stack);
    // Keep native owner and retry responsibility; never auto-ACK a failed conversion.
    unawaited(_controller.close());
  }

  Future<void> acknowledge(int deliverySequence) async {
    if (_admissionsClosed) throw _conversationClosedFailure;
    _validateConversationUnsigned(deliverySequence);
    await FrbStudioTransport._bridgeCall(() async {
      _nativeAcknowledge(deliverySequence);
    });
  }

  void requestClose() {
    if (_closed) return;
    _closed = true;
    _requestCloseChildren();
    try {
      _nativeRequestClose();
    } catch (_) {
      /* close retains typed failure responsibility */
    }
  }

  Future<void> close() {
    requestClose();
    final existing = _closing;
    if (existing != null) return existing;
    final work = _joinClose();
    _closing = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_closing, work)) _closing = null;
        },
      ),
    );
    return work;
  }

  Future<void> _joinClose() async {
    try {
      final registration = _registration;
      if (registration == null) {
        await _releaseNative();
      } else {
        await registration.beginCancel();
      }
    } catch (error, stack) {
      Error.throwWithStackTrace(_studioFailure(error), stack);
    }
  }

  Future<void> _releaseNative() {
    requestClose();
    final existing = _nativeClosing;
    if (existing != null) return existing;
    final work = _joinNative();
    _nativeClosing = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_nativeClosing, work)) _nativeClosing = null;
        },
      ),
    );
    return work;
  }

  Future<void> _joinNative() async {
    try {
      Object? failure;
      StackTrace? failureStack;
      await Future.wait(
        [Future<void>.sync(_nativeClose), ..._closeChildren()].map(
          (task) => task.then<void>(
            (_) {},
            onError: (Object error, StackTrace stack) {
              failure ??= error;
              failureStack ??= stack;
            },
          ),
        ),
      );
      // Native close is joined BEFORE cancelling the held native stream. No cycle with
      // the public controller's onCancel, which awaits this same native join.
      try {
        await _subscription?.cancel();
        _subscription = null;
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
      if (failure != null) {
        Error.throwWithStackTrace(failure!, failureStack!);
      }
      if (!_disposed) {
        _nativeDispose();
        _disposed = true;
      }
      if (_listened) unawaited(_controller.close());
    } catch (error, stack) {
      Error.throwWithStackTrace(_studioFailure(error), stack);
    }
  }
}

const _conversationClosedFailure = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The conversation feed is closed',
  retryable: false,
  correlationId: 'client-conversation-closed',
);
const _conversationQueryFailure = StudioFailure(
  code: StudioFailureCode.invalidArgument,
  message: 'The conversation query is invalid',
  retryable: false,
  correlationId: 'client-conversation-query',
);
void _validateConversationUnsigned(int value) {
  if (value < 0 || BigInt.from(value) > (BigInt.one << 64) - BigInt.one) {
    throw _conversationQueryFailure;
  }
}

int _exactTimelineInt(BigInt value, String what) {
  final result = value.toInt();
  if (value.isNegative || result < 0 || BigInt.from(result) != value) {
    throw StudioFailure(
      code: StudioFailureCode.overloaded,
      message: 'Conversation $what cannot be represented exactly',
      retryable: false,
      correlationId: 'client-conversation-range',
    );
  }
  return result;
}

int? _exactNullableTimelineInt(BigInt? value, String what) =>
    value == null ? null : _exactTimelineInt(value, what);

int _exactSignedTimelineInt(Object value) {
  final integer = switch (value) {
    final BigInt n => n,
    final int n => BigInt.from(n),
    _ => throw const StudioFailure(
      code: StudioFailureCode.internal,
      message: 'Conversation timestamp is not an integer',
      retryable: false,
      correlationId: 'client-conversation-integer-type',
    ),
  };
  final converted = integer.toInt();
  if (BigInt.from(converted) != integer) {
    throw const StudioFailure(
      code: StudioFailureCode.overloaded,
      message: 'Conversation timestamp cannot be represented exactly',
      retryable: false,
      correlationId: 'client-conversation-range',
    );
  }
  return converted;
}
