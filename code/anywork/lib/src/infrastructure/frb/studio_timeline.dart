part of 'studio_api.dart';

/// Immutable history query owner. It has no delivery cursor, ACK or UI state.
final class FrbHistoryReader extends _FrbPortProxy<_FrbRawHistoryReader>
    implements HistoryReader {
  FrbHistoryReader._(super.entry, super.raw);

  @override
  OpenHistory get metadata => _raw.metadata;
  @override
  String get threadId => _raw.threadId;

  @override
  Future<HistoryCut> capture() => _raw.capture();
  @override
  Future<HistoryTimelinePage> timelinePage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _raw.timelinePage(cut: cut, cursor: cursor, demand: demand);
  @override
  Future<HistoryGroupPage> groupPage({
    required String groupId,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _raw.groupPage(
    groupId: groupId,
    cut: cut,
    cursor: cursor,
    demand: demand,
  );
  @override
  Future<HistoryTimelinePage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _raw.turnsPage(cut: cut, cursor: cursor, demand: demand);
  @override
  Future<HistoryEventsPage> eventsPage({
    required HistoryEventsQuery query,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _raw.eventsPage(query: query, cut: cut, cursor: cursor, demand: demand);
  @override
  Future<HistoryEventDetail> readEvent({
    required String eventId,
    required HistoryDemand demand,
  }) => _raw.readEvent(eventId: eventId, demand: demand);
  @override
  Future<HistoryBodyPage> listBodies({
    required String eventId,
    String? cursor,
    required HistoryDemand demand,
  }) => _raw.listBodies(eventId: eventId, cursor: cursor, demand: demand);
  @override
  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  }) => _raw.readBody(reference: reference, offset: offset, maxBytes: maxBytes);
  @override
  Future<HistoryAccounting?> accounting({HistoryCut? cut}) =>
      _raw.accounting(cut: cut);
  @override
  Future<HistoryTimelinePage> costsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _raw.costsPage(cut: cut, cursor: cursor, demand: demand);
  @override
  Future<HistoryCut> waitChanged(HistoryCut after) => _raw.waitChanged(after);
}

final class _FrbRawHistoryReader extends _FrbRawResource {
  _FrbRawHistoryReader(
    super.resourceId,
    frb_timeline.BridgeHistoryReader handle,
  ) : _handle = handle;
  frb_timeline.BridgeHistoryReader? _handle;
  frb_timeline.BridgeHistoryReader get history => _handle!;
  late final String threadId = history.threadId();
  late final OpenHistory metadata = _openHistoryFromFrb(history.metadata());

  void _checkOpen() {
    if (stopping) throw _conversationClosedFailure;
  }

  Future<HistoryCut> capture() => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await history.capture();
    _checkOpen();
    return _historyCutFromFrb(value);
  });

  Future<HistoryTimelinePage> timelinePage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await history.timelinePage(
      cut: cut == null ? null : _historyCutToFrb(cut),
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    );
    _checkOpen();
    return _historyTimelinePageFromFrb(value);
  });

  Future<HistoryGroupPage> groupPage({
    required String groupId,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await history.groupPage(
      groupId: groupId,
      cut: cut == null ? null : _historyCutToFrb(cut),
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    );
    _checkOpen();
    return _historyGroupPageFromFrb(value);
  });

  Future<HistoryTimelinePage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await history.turnsPage(
      cut: cut == null ? null : _historyCutToFrb(cut),
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    );
    _checkOpen();
    return _historyTimelinePageFromFrb(value);
  });

  Future<HistoryEventsPage> eventsPage({
    required HistoryEventsQuery query,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await history.eventsPage(
      query: _historyEventsQueryToFrb(query),
      cut: cut == null ? null : _historyCutToFrb(cut),
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    );
    _checkOpen();
    return _historyEventsPageFromFrb(value);
  });

  Future<HistoryEventDetail> readEvent({
    required String eventId,
    required HistoryDemand demand,
  }) => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await history.readEvent(
      eventId: eventId,
      demand: _historyDemandToFrb(demand),
    );
    _checkOpen();
    return _historyEventDetailFromFrb(value);
  });

  Future<HistoryBodyPage> listBodies({
    required String eventId,
    String? cursor,
    required HistoryDemand demand,
  }) => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await history.listBodies(
      eventId: eventId,
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    );
    _checkOpen();
    return _historyBodyPageFromFrb(value);
  });

  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  }) => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await history.readBody(
      reference: _historyBodyRefToFrb(reference),
      offset: BigInt.from(offset),
      maxBytes: maxBytes,
    );
    _checkOpen();
    return _historyBodyWindowFromFrb(value);
  });

  Future<HistoryAccounting?> accounting({HistoryCut? cut}) =>
      FrbStudioTransport._bridgeCall(() async {
        _checkOpen();
        final value = await history.accounting(
          cut: cut == null ? null : _historyCutToFrb(cut),
        );
        _checkOpen();
        return _historyAccountingFromFrb(value);
      });

  Future<HistoryTimelinePage> costsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await history.costsPage(
      cut: cut == null ? null : _historyCutToFrb(cut),
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    );
    _checkOpen();
    return _historyTimelinePageFromFrb(value);
  });

  Future<HistoryCut> waitChanged(HistoryCut after) =>
      FrbStudioTransport._bridgeCall(() async {
        _checkOpen();
        final value = await history.waitChanged(after: _historyCutToFrb(after));
        _checkOpen();
        return _historyCutFromFrb(value);
      });

  @override
  void requestNativeClose() => history.requestClose();
  @override
  Future<void> cancelNative() => FrbStudioTransport._bridgeCall(history.close);
  @override
  void disposeNative() {
    history.dispose();
    _handle = null;
  }
}

final class FrbCurrentReader extends _FrbPortProxy<_FrbRawCurrentReader>
    implements CurrentReader {
  FrbCurrentReader._(super.entry, super.raw);
  @override
  OpenCurrent get metadata => _raw.metadata;
  @override
  String get threadId => _raw.threadId;
  @override
  CurrentView get initialView => _raw.initialView;
  @override
  Future<CurrentView> snapshot(ReadDemand demand) => _raw.snapshot(demand);
  @override
  Future<CurrentWatch> watch({
    CurrentRevision? after,
    required ReadDemand demand,
  }) => _raw.watch(after: after, demand: demand);
  @override
  Future<CurrentCollectionPage> pageCollection({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) => _raw.pageCollection(
    reference: reference,
    continuation: continuation,
    demand: demand,
  );
  @override
  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) => _raw.readBody(reference: reference, range: range);
  @override
  Future<CurrentBodyWatch> watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) => _raw.watchBody(reference: reference, range: range);
}

final class _FrbRawCurrentReader extends _FrbRawResource {
  _FrbRawCurrentReader(
    super.resourceId,
    frb_timeline.BridgeCurrentReader handle,
    this.contentScope,
    this.ensureReady,
  ) : _handle = handle;
  frb_timeline.BridgeCurrentReader? _handle;
  frb_timeline.BridgeCurrentReader get current => _handle!;
  final ClientScope contentScope;
  final Future<void> Function() ensureReady;
  late final String threadId = current.threadId();
  late final OpenCurrent metadata = _openCurrentFromFrb(current.metadata());
  late final CurrentView initialView = _currentViewFromFrb(
    current.initialView(),
  );

  void _checkOpen() {
    if (stopping) throw _conversationClosedFailure;
  }

  Future<CurrentView> snapshot(ReadDemand demand) =>
      FrbStudioTransport._bridgeCall(() async {
        _checkOpen();
        final value = await current.snapshot(demand: _readDemandToFrb(demand));
        _checkOpen();
        return _currentViewFromFrb(value);
      });

  Future<CurrentWatch> watch({
    CurrentRevision? after,
    required ReadDemand demand,
  }) {
    _checkOpen();
    final entry = contentScope
        .open<_FrbRawPull<frb_timeline.BridgeCurrentWatch, CurrentFrame>>(
          'current-watch',
          (operation) async {
            await ensureReady();
            final handle = await FrbStudioTransport._bridgeCall(
              () => current.watch(
                after: after == null ? null : _currentRevisionToFrb(after),
                demand: _readDemandToFrb(demand),
              ),
            );
            return _FrbRawPull(
              operation.resourceId,
              handle,
              (handle) async {
                final value = await handle.next();
                return value == null ? null : _currentFrameFromFrb(value);
              },
              (handle) => handle.requestClose(),
              (handle) => handle.close(),
              (handle) => handle.dispose(),
            );
          },
        );
    return Future.value(_FrbCurrentWatch(entry));
  }

  Future<CurrentCollectionPage> pageCollection({
    required CurrentCollectionRef reference,
    String? continuation,
    required ReadDemand demand,
  }) => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await current.pageCollection(
      reference: _currentCollectionRefToFrb(reference),
      continuation: continuation,
      demand: _readDemandToFrb(demand),
    );
    _checkOpen();
    return _currentCollectionPageFromFrb(value);
  });

  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) => FrbStudioTransport._bridgeCall(() async {
    _checkOpen();
    final value = await current.readBody(
      reference: _currentContentRefToFrb(reference),
      range: _contentRangeToFrb(range),
    );
    _checkOpen();
    return _contentWindowFromFrb(value);
  });

  Future<CurrentBodyWatch> watchBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) {
    _checkOpen();
    final entry = contentScope
        .open<_FrbRawPull<frb_timeline.BridgeCurrentBodyWatch, ContentWindow>>(
          'current-body-watch',
          (operation) async {
            await ensureReady();
            final handle = await FrbStudioTransport._bridgeCall(
              () => current.watchBody(
                reference: _currentContentRefToFrb(reference),
                range: _contentRangeToFrb(range),
              ),
            );
            return _FrbRawPull(
              operation.resourceId,
              handle,
              (handle) async {
                final value = await handle.next();
                return value == null ? null : _contentWindowFromFrb(value);
              },
              (handle) => handle.requestClose(),
              (handle) => handle.close(),
              (handle) => handle.dispose(),
            );
          },
        );
    return Future.value(_FrbCurrentBodyWatch(entry));
  }

  @override
  void stopDelivery() => contentScope.requestClose();
  @override
  void requestNativeClose() => current.requestClose();
  @override
  Future<void> cancelNative() => FrbStudioTransport._bridgeCall(current.close);
  @override
  void disposeNative() {
    current.dispose();
    _handle = null;
  }
}

final class _FrbCurrentWatch implements CurrentWatch {
  _FrbCurrentWatch(this._entry) {
    _output = StreamController(onListen: _start, onCancel: requestClose);
  }
  final ClientAcquisition<
    _FrbRawPull<frb_timeline.BridgeCurrentWatch, CurrentFrame>
  >
  _entry;
  late final StreamController<CurrentFrame> _output;
  Future<void>? _pumping;
  bool _started = false;
  bool _closed = false;

  @override
  Stream<CurrentFrame> get frames => _output.stream;

  void _start() {
    if (_started || _closed) return;
    _started = true;
    final completion = Completer<void>();
    _pumping = completion.future;
    completion.complete(
      Future<void>.sync(() async {
        try {
          final raw = await _entry.ready;
          while (!_closed) {
            final frame = await raw.next();
            if (_closed) return;
            if (frame == null) break;
            _output.add(frame);
          }
          await _endOutput();
        } catch (error, stack) {
          if (!_closed) {
            _output.addError(_studioFailure(error), stack);
            requestClose();
          }
          await _endOutput();
        }
      }),
    );
  }

  Future<void> _endOutput() async {
    if (!_output.isClosed) await _output.close();
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    _entry.requestClose();
  }

  @override
  Future<void> close() async {
    requestClose();
    try {
      await _entry.close();
    } finally {
      await _pumping;
      await _endOutput();
    }
  }
}

final class _FrbCurrentBodyWatch implements CurrentBodyWatch {
  _FrbCurrentBodyWatch(this._entry) {
    _output = StreamController(onListen: _start, onCancel: requestClose);
  }
  final ClientAcquisition<
    _FrbRawPull<frb_timeline.BridgeCurrentBodyWatch, ContentWindow>
  >
  _entry;
  late final StreamController<ContentWindow> _output;
  Future<void>? _pumping;
  bool _started = false;
  bool _closed = false;

  @override
  Stream<ContentWindow> get windows => _output.stream;

  void _start() {
    if (_started || _closed) return;
    _started = true;
    final completion = Completer<void>();
    _pumping = completion.future;
    completion.complete(
      Future<void>.sync(() async {
        try {
          final raw = await _entry.ready;
          while (!_closed) {
            final window = await raw.next();
            if (_closed) return;
            if (window == null) break;
            _output.add(window);
          }
          await _endOutput();
        } catch (error, stack) {
          if (!_closed) {
            _output.addError(_studioFailure(error), stack);
            requestClose();
          }
          await _endOutput();
        }
      }),
    );
  }

  Future<void> _endOutput() async {
    if (!_output.isClosed) await _output.close();
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    _entry.requestClose();
  }

  @override
  Future<void> close() async {
    requestClose();
    try {
      await _entry.close();
    } finally {
      await _pumping;
      await _endOutput();
    }
  }
}
