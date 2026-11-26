part of 'studio_api.dart';

final class FrbConversationFeedHandle
    extends _FrbPortProxy<_FrbRawConversationFeed>
    implements ConversationFeedHandle {
  FrbConversationFeedHandle._(super.entry, super.raw)
    : threadId = raw.handle.threadId();

  @override
  final String threadId;

  @override
  LiveStatusSnapshot get liveStatusSnapshot =>
      _snapshot(() => _liveStatusFromFrb(_raw.handle.liveStatusSnapshot()));

  @override
  SessionMetaSnapshot get sessionMetaSnapshot =>
      _snapshot(() => _sessionMetaFromFrb(_raw.handle.sessionMetaSnapshot()));

  T _snapshot<T>(T Function() read) {
    try {
      _raw._checkOpen();
      return read();
    } catch (error, stack) {
      Error.throwWithStackTrace(_studioFailure(error), stack);
    }
  }

  @override
  Stream<ConversationFeedEvent> get events => _raw.events;

  @override
  Future<TimelinePatch> loadOlder({required String cursor, int limit = 50}) =>
      _raw._guardedCall(
        () => _raw.handle.loadOlder(cursor: cursor, limit: limit),
        _timelinePatchFromFrb,
      );

  @override
  Future<List<WorkGroupMember>> loadWorkGroupMembers({
    int? afterSeq,
    int? beforeSeq,
  }) => _raw._guardedCall(
    () => _raw.handle.loadWorkGroupMembers(
      afterSeq: afterSeq == null ? null : BigInt.from(afterSeq),
      beforeSeq: beforeSeq == null ? null : BigInt.from(beforeSeq),
    ),
    (members) => List.unmodifiable(members.map(_workGroupMemberFromFrb)),
  );

  @override
  Future<BodyWindow> readBodyWindow({
    required BodyRef reference,
    required int offset,
    required int maxBytes,
  }) => _raw._guardedCall(
    () => _raw.handle.readBodyWindow(
      reference: _bodyRefToFrb(reference),
      offset: BigInt.from(offset),
      maxBytes: maxBytes,
    ),
    _bodyWindowFromFrb,
  );

  @override
  Future<SessionDetailWindow> readSessionDetail({
    required SessionDetailKind kind,
    required int offset,
    required int maxBytes,
  }) => _raw._guardedCall(() {
    if (offset < 0 || maxBytes < 0) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Invalid session detail window',
        retryable: false,
        correlationId: 'client-session-detail-range',
      );
    }
    return _raw.handle.readSessionDetail(
      kind: _sessionDetailKindToFrb(kind),
      offset: BigInt.from(offset),
      maxBytes: maxBytes.clamp(1, 64 * 1024),
    );
  }, _sessionDetailWindowFromFrb);

  @override
  Future<TimelinePatch> resetToLatest({int limit = 50}) => _raw._guardedCall(
    () => _raw.handle.resetToLatest(limit: limit),
    _timelinePatchFromFrb,
  );
}

final class _FrbRawConversationFeed
    extends
        _FrbRawPull<
          frb_timeline.BridgeConversationFeed,
          ConversationFeedEvent
        > {
  _FrbRawConversationFeed(
    ClientResourceId resourceId,
    frb_timeline.BridgeConversationFeed handle,
  ) : super(
        resourceId,
        handle,
        (handle) async {
          final event = await handle.nextEvent();
          return event == null ? null : _conversationEventFromFrb(event);
        },
        (handle) => handle.requestClose(),
        (handle) => handle.close(),
        (handle) => handle.dispose(),
      ) {
    _events = StreamController(onListen: _startPump, onResume: _startPump);
  }

  late final StreamController<ConversationFeedEvent> _events;
  Future<void>? _pumping;

  late final Stream<ConversationFeedEvent> events = _events.stream.takeWhile(
    (_) => !stopping,
  );

  void bind(ClientAcquisition<_FrbRawConversationFeed> entry) {
    _events.onCancel = entry.requestClose;
  }

  void _startPump() {
    if (stopping || _pumping != null) return;
    final done = Completer<void>();
    _pumping = done.future;
    done.complete(_pump());
  }

  Future<void> _pump() async {
    try {
      while (!stopping && !_events.isPaused) {
        final event = await next();
        if (stopping) break;
        if (event == null) {
          unawaited(_events.close());
          break;
        }
        _events.add(event);
      }
    } catch (error, stack) {
      if (!stopping) {
        _events.addError(_studioFailure(error), stack);
        if (!_events.isClosed) unawaited(_events.close());
      }
    } finally {
      _pumping = null;
    }
  }

  @override
  void stopDelivery() {
    if (!_events.isClosed) unawaited(_events.close());
  }

  @override
  Future<void> closeDart() async {
    await super.closeDart();
    await _pumping;
  }
}
