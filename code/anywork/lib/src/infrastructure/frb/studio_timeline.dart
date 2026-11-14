part of 'studio_api.dart';

final class FrbTimelineReader implements TimelineReader, _FrbContentOwner {
  FrbTimelineReader(this._timeline)
    : _native = _FrbNativeReader.timeline(_timeline),
      metadata = _openTimelineFromFrb(_timeline.metadata());
  final frb_timeline.BridgeTimelineReader _timeline;
  @override
  final _FrbNativeReader _native;
  @override
  final OpenTimeline metadata;
  @override
  late final ConversationReader reader = _FrbConversationReader(this);
  @override
  String get threadId => _native.threadId();
  @override
  final Set<_FrbContentWatch> _contentWatches = {};
  final Set<_FrbDisplayMembers> _memberWatches = {};
  _DartSubscription? _registration;
  bool _closed = false;
  bool _disposed = false;
  Future<void>? _closing;
  Future<void>? _nativeClosing;
  @override
  bool get _admissionsClosed =>
      _closed || (_registration?.cancelRequested ?? false);

  @override
  Future<ViewUpdate> next({required ViewCursor after}) =>
      FrbStudioTransport._bridgeCall(() async {
        if (_admissionsClosed) throw _conversationClosedFailure;
        final value = await _timeline.next(after: after.value);
        if (_admissionsClosed) throw _conversationClosedFailure;
        return _viewUpdateFromFrb(value);
      });

  @override
  void requestClose() {
    _closed = true;
    _timeline.requestClose();
    for (final watch in List.of(_contentWatches)) {
      watch.requestClose();
    }
    for (final watch in List.of(_memberWatches)) {
      watch.requestClose();
    }
  }

  @override
  Future<void> close() {
    requestClose();
    final existing = _closing;
    if (existing != null) return existing;
    final work = _registration?.beginCancel() ?? _releaseNative();
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
    await Future.wait<void>([
      FrbStudioTransport._bridgeCall(_timeline.close),
      for (final watch in List.of(_contentWatches)) watch.close(),
      for (final watch in List.of(_memberWatches)) watch.close(),
    ]);
    if (!_disposed) {
      _timeline.dispose();
      _disposed = true;
    }
  }

  @override
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) {
    if (_admissionsClosed) throw _conversationClosedFailure;
    return FrbStudioTransport._bridgeCall(() async {
      final batch = await _timeline.loadOlder(
        before: before,
        demand: _readDemandToFrb(demand),
      );
      if (_admissionsClosed) throw _conversationClosedFailure;
      return _timelinePageFromFrb(batch);
    });
  }

  @override
  Future<TailSnapshot> loadLiveOlder({
    required String before,
    required ReadDemand demand,
  }) {
    if (_admissionsClosed) throw _conversationClosedFailure;
    return FrbStudioTransport._bridgeCall(() async {
      final window = await _timeline.loadLiveOlder(
        before: before,
        demand: _readDemandToFrb(demand),
      );
      if (_admissionsClosed) throw _conversationClosedFailure;
      return _tailSnapshotFromFrb(window);
    });
  }

  @override
  Future<DisplayMembers> openDisplayMembers({
    required DisplayBlockRef reference,
    required DisplayMemberWindow window,
    required ReadDemand demand,
  }) async {
    if (_admissionsClosed) throw _conversationClosedFailure;
    // Register before the first await so close also joins a late native open.
    final watch = _FrbDisplayMembers(this);
    _memberWatches.add(watch);
    watch._opening = FrbStudioTransport._bridgeCall(
      () => _timeline.openDisplayMembers(
        reference: _displayBlockRefToFrb(reference),
        window: _displayMemberWindowToFrb(window),
        demand: _readDemandToFrb(demand),
      ),
    );
    try {
      watch._handle = await watch._opening;
      if (_admissionsClosed || watch._closed) {
        watch.requestClose();
        await watch.close();
        throw _conversationClosedFailure;
      }
      return watch;
    } catch (error, stack) {
      try {
        await watch.close();
      } catch (_) {
        /* retained for parent close */
      }
      Error.throwWithStackTrace(_studioFailure(error), stack);
    }
  }
}

final class _FrbDisplayMembers implements DisplayMembers {
  _FrbDisplayMembers(this._feed);
  final FrbTimelineReader _feed;
  late final Future<frb_timeline.BridgeDisplayMembers> _opening;
  frb_timeline.BridgeDisplayMembers? _handle;
  Future<void>? _closing;
  Future<DisplayMemberPage?>? _reading;
  bool _closed = false;
  bool _disposed = false;

  @override
  Future<DisplayMemberPage?> next() {
    if (_closed || _feed._admissionsClosed) throw _conversationClosedFailure;
    if (_reading != null) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'A display member read is already in flight',
        retryable: false,
        correlationId: 'client-display-members-concurrent-next',
      );
    }
    final work = _next();
    _reading = work;
    unawaited(
      work.then<void>(
        (_) {
          if (identical(_reading, work)) _reading = null;
        },
        onError: (Object _, StackTrace _) {
          if (identical(_reading, work)) _reading = null;
        },
      ),
    );
    return work;
  }

  Future<DisplayMemberPage?> _next() async {
    try {
      final handle = _handle ??= await _opening;
      final page = await FrbStudioTransport._bridgeCall(handle.next);
      if (_closed || _feed._admissionsClosed) throw _conversationClosedFailure;
      return page == null ? null : _displayMemberPageFromFrb(page);
    } catch (error, stack) {
      Error.throwWithStackTrace(_studioFailure(error), stack);
    }
  }

  @override
  void requestClose() {
    _closed = true;
    try {
      _handle?.requestClose();
    } catch (_) {
      /* close retains the error */
    }
  }

  @override
  Future<void> close() {
    requestClose();
    final existing = _closing;
    if (existing != null) return existing;
    final work = _join();
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

  Future<void> _join() async {
    frb_timeline.BridgeDisplayMembers handle;
    try {
      handle = _handle ??= await _opening;
    } catch (_) {
      // Native open owns its unpublished cleanup. No handle was issued here.
      _feed._memberWatches.remove(this);
      return;
    }
    handle.requestClose();
    await FrbStudioTransport._bridgeCall(handle.close);
    try {
      await _reading;
    } catch (_) {
      /* the next caller retains its result */
    }
    if (!_disposed) {
      handle.dispose();
      _disposed = true;
    }
    _feed._memberWatches.remove(this);
  }
}
