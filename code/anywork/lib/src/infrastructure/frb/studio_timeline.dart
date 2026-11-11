part of 'studio_api.dart';

final class FrbTimelineFeed extends FrbConversationFeed
    implements TimelineFeed {
  FrbTimelineFeed(this._timeline)
    : super._(_FrbNativeConversation.timeline(_timeline));

  final frb_timeline.BridgeTimelineFeed _timeline;

  @override
  Future<TimelineBatch> loadTimelineOlder({
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
      return _timelineBatchFromFrb(batch);
    });
  }

  @override
  Future<LiveDisplayWindow> loadLiveOlder({
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
      return _liveDisplayWindowFromFrb(window);
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
  final FrbTimelineFeed _feed;
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
