part of 'studio_api.dart';

/// Mechanical port proxy. The scope entry, not this proxy, owns the native feed.
final class FrbConversationFeed extends _FrbPortProxy<_FrbRawConversationFeed>
    implements ConversationFeed, _FrbContentOwner {
  FrbConversationFeed._(super.entry, super.raw);
  @override
  String get threadId => _raw.threadId;
  @override
  String get subscriptionId => _raw.subscriptionId;
  @override
  Stream<ConversationFrame> get events => _raw.events;
  @override
  Future<void> acknowledge(int deliverySequence) =>
      _raw.acknowledge(deliverySequence);
  @override
  late final ConversationReader reader = _FrbConversationReader(this);
  @override
  bool get _admissionsClosed => _raw.stopping;
  @override
  _FrbNativeConversation get _native => _raw.native;
  @override
  Set<_FrbContentWatch> get _contentWatches => _raw.contentWatches;
}

final class _FrbRawConversationFeed extends _FrbRawConversationDelivery {
  _FrbRawConversationFeed(
    super.resourceId,
    frb_chat.BridgeConversationFeed handle,
  ) : _handle = handle;
  frb_chat.BridgeConversationFeed? _handle;
  _FrbNativeConversation? _reader;
  _FrbNativeConversation get native =>
      _reader ??= _FrbNativeConversation.conversation(_handle!);
  final Set<_FrbContentWatch> contentWatches = {};
  @override
  late final String threadId = native.threadId();
  @override
  late final String subscriptionId = native.subscriptionId();
  @override
  Stream<frb_chat_types.BridgeConversationFrame> _nativeEvents() =>
      native.events();
  @override
  void _nativeAcknowledge(int sequence) => native.acknowledge(
    subscriptionId: subscriptionId,
    deliverySequence: BigInt.from(sequence),
  );
  @override
  void requestNativeClose() => native.requestClose();
  @override
  Future<void> cancelNative() => FrbStudioTransport._bridgeCall(native.close);
  @override
  void disposeNative() {
    _handle!.dispose();
    _handle = null;
    _reader = null;
  }

  @override
  void stopDelivery() {
    super.stopDelivery();
    for (final watch in List.of(contentWatches)) {
      watch.requestClose();
    }
  }

  @override
  Future<void> closeChildren() => Future.wait<void>([
    for (final watch in List.of(contentWatches)) Future<void>.sync(watch.close),
  ]);
}

/// Only FRB conversion and the single-consumer rule live here. ClientScope owns
/// close futures and failed-close retention; raw layer completion lives in base.
abstract class _FrbRawConversationDelivery extends _FrbRawResource {
  _FrbRawConversationDelivery(super.resourceId);
  String get threadId;
  String get subscriptionId;
  Stream<frb_chat_types.BridgeConversationFrame> _nativeEvents();
  void _nativeAcknowledge(int sequence);
  void Function()? requestCleanup;
  bool _listened = false;
  StreamSubscription<frb_chat_types.BridgeConversationFrame>? _subscription;
  late final StreamController<ConversationFrame> _controller = StreamController(
    onListen: _listen,
  );

  Stream<ConversationFrame> get events {
    if (stopping) throw _conversationClosedFailure;
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
    if (stopping) {
      _observeBackground(_controller.close());
      return;
    }
    try {
      _subscription = _nativeEvents().listen(
        (value) {
          if (stopping) return;
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
                  frb_chat_types.BridgeConversationEvent_Chat(:final batch) =>
                    ConversationChatEvent(batch: _chatBatchFromFrb(batch)),
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
          _observeBackground(_controller.close());
        },
      );
    } catch (error, stack) {
      _conversionFailed(error, stack);
    }
  }

  void _conversionFailed(Object error, StackTrace stack) {
    if (stopping) return;
    _controller.addError(_studioFailure(error), stack);
    requestCleanup?.call();
  }

  Future<void> acknowledge(int deliverySequence) async {
    if (stopping) throw _conversationClosedFailure;
    _validateConversationUnsigned(deliverySequence);
    await FrbStudioTransport._bridgeCall(() async {
      _nativeAcknowledge(deliverySequence);
    });
  }

  @override
  void stopDelivery() => _observeBackground(_controller.close());

  @override
  Future<void> closeDart() async {
    final subscription = _subscription;
    if (subscription != null) {
      await subscription.cancel();
      _subscription = null;
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
