part of 'studio_api.dart';

final class FrbTimelineReader extends _FrbPortProxy<_FrbRawTimelineReader>
    implements TimelineReader, _FrbContentOwner {
  FrbTimelineReader._(super.entry, super.raw);
  @override
  OpenTimeline get metadata => _raw.metadata;
  @override
  String get threadId => _raw.threadId;
  @override
  late final ConversationReader reader = _FrbConversationReader(this);
  @override
  _FrbNativeReader get _native => _raw.native;
  @override
  Set<_FrbContentWatch> get _contentWatches => _raw.contentWatches;
  @override
  bool get _admissionsClosed => _raw.stopping;

  @override
  Future<ViewUpdate> next({required ViewCursor after}) =>
      FrbStudioTransport._bridgeCall(() async {
        if (_admissionsClosed) throw _conversationClosedFailure;
        final value = await _raw.timeline.next(after: after.value);
        if (_admissionsClosed) throw _conversationClosedFailure;
        return _viewUpdateFromFrb(value);
      });

  @override
  Future<TimelinePage> loadTimelineOlder({
    required String before,
    required ReadDemand demand,
  }) {
    if (_admissionsClosed) throw _conversationClosedFailure;
    return FrbStudioTransport._bridgeCall(() async {
      final batch = await _raw.timeline.loadOlder(
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
      final window = await _raw.timeline.loadLiveOlder(
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
    required ReadDemand demand,
  }) {
    if (_admissionsClosed) throw _conversationClosedFailure;
    final entry = _raw.membersScope
        .open<
          _FrbRawPull<frb_timeline.BridgeDisplayMembers, DisplayMemberBatch>
        >('display-members', (operation) async {
          final handle = await FrbStudioTransport._bridgeCall(
            () => _raw.timeline.openDisplayMembers(
              reference: _displayBlockRefToFrb(reference),
              demand: _readDemandToFrb(demand),
            ),
          );
          return _FrbRawPull(
            operation.resourceId,
            handle,
            (handle) async {
              final page = await handle.next();
              if (_admissionsClosed) throw _conversationClosedFailure;
              return page == null ? null : _displayMemberBatchFromFrb(page);
            },
            (handle) => handle.requestClose(),
            (handle) => handle.close(),
            (handle) => handle.dispose(),
          );
        });
    return _publishRaw(entry, (raw) => _FrbDisplayMembers(entry, raw));
  }
}

final class _FrbRawTimelineReader extends _FrbRawResource {
  _FrbRawTimelineReader(
    super.resourceId,
    frb_timeline.BridgeTimelineReader handle,
    this.membersScope,
  ) : _handle = handle;
  frb_timeline.BridgeTimelineReader? _handle;
  frb_timeline.BridgeTimelineReader get timeline => _handle!;
  final ClientScope membersScope;
  _FrbNativeReader? _reader;
  _FrbNativeReader get native =>
      _reader ??= _FrbNativeReader.timeline(timeline);
  late final String threadId = timeline.threadId();
  late final OpenTimeline metadata = _openTimelineFromFrb(timeline.metadata());
  final Set<_FrbContentWatch> contentWatches = {};
  @override
  void stopDelivery() {
    membersScope.requestClose();
    for (final watch in List.of(contentWatches)) {
      watch.requestClose();
    }
  }

  @override
  void requestNativeClose() => timeline.requestClose();
  @override
  Future<void> cancelNative() => FrbStudioTransport._bridgeCall(timeline.close);
  @override
  void disposeNative() {
    timeline.dispose();
    _handle = null;
    _reader = null;
  }

  @override
  Future<void> closeChildren() async {
    // Native timeline close joins its member watches. Their Dart-owned handles
    // remain in membersScope until their own ACK/dispose, including late opens.
    await Future.wait<void>([
      for (final watch in List.of(contentWatches))
        Future<void>.sync(watch.close),
    ]);
  }
}

final class _FrbDisplayMembers
    extends
        _FrbPortProxy<
          _FrbRawPull<frb_timeline.BridgeDisplayMembers, DisplayMemberBatch>
        >
    implements DisplayMembers {
  _FrbDisplayMembers(super.entry, super.raw);
  @override
  Future<DisplayMemberBatch?> next() => _raw.next();
}
