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
  Future<HistoryWorkRangePage> workRangePage({
    int? afterSeq,
    int? beforeSeq,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _raw.workRangePage(
    afterSeq: afterSeq,
    beforeSeq: beforeSeq,
    cut: cut,
    cursor: cursor,
    demand: demand,
  );
  @override
  Future<HistoryBusinessPage> turnsPage({
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
  Future<HistoryEventRecord> readEvent({
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
  Future<HistoryBusinessPage> costsPage({
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

  Future<HistoryCut> capture() =>
      _guardedCall(history.capture, _historyCutFromFrb);

  Future<HistoryTimelinePage> timelinePage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _guardedCall(
    () => history.timelinePage(
      cut: cut == null ? null : _historyCutToFrb(cut),
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    ),
    _historyTimelinePageFromFrb,
  );

  Future<HistoryWorkRangePage> workRangePage({
    int? afterSeq,
    int? beforeSeq,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _guardedCall(
    () => history.workRangePage(
      afterSeq: afterSeq == null ? null : BigInt.from(afterSeq),
      beforeSeq: beforeSeq == null ? null : BigInt.from(beforeSeq),
      cut: cut == null ? null : _historyCutToFrb(cut),
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    ),
    _historyWorkRangePageFromFrb,
  );

  Future<HistoryBusinessPage> turnsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _guardedCall(
    () => history.turnsPage(
      cut: cut == null ? null : _historyCutToFrb(cut),
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    ),
    _historyBusinessPageFromFrb,
  );

  Future<HistoryEventsPage> eventsPage({
    required HistoryEventsQuery query,
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _guardedCall(
    () => history.eventsPage(
      query: _historyEventsQueryToFrb(query),
      cut: cut == null ? null : _historyCutToFrb(cut),
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    ),
    _historyEventsPageFromFrb,
  );

  Future<HistoryEventRecord> readEvent({
    required String eventId,
    required HistoryDemand demand,
  }) => _guardedCall(
    () => history.readEvent(
      eventId: eventId,
      demand: _historyDemandToFrb(demand),
    ),
    _historyEventRecordFromFrb,
  );

  Future<HistoryBodyPage> listBodies({
    required String eventId,
    String? cursor,
    required HistoryDemand demand,
  }) => _guardedCall(
    () => history.listBodies(
      eventId: eventId,
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    ),
    _historyBodyPageFromFrb,
  );

  Future<HistoryBodyWindow> readBody({
    required HistoryEventBodyRef reference,
    required int offset,
    required int maxBytes,
  }) => _guardedCall(
    () => history.readBody(
      reference: _historyBodyRefToFrb(reference),
      offset: BigInt.from(offset),
      maxBytes: maxBytes,
    ),
    _historyBodyWindowFromFrb,
  );

  Future<HistoryAccounting?> accounting({HistoryCut? cut}) => _guardedCall(
    () => history.accounting(cut: cut == null ? null : _historyCutToFrb(cut)),
    _historyAccountingFromFrb,
  );

  Future<HistoryBusinessPage> costsPage({
    HistoryCut? cut,
    String? cursor,
    required HistoryDemand demand,
  }) => _guardedCall(
    () => history.costsPage(
      cut: cut == null ? null : _historyCutToFrb(cut),
      cursor: cursor,
      demand: _historyDemandToFrb(demand),
    ),
    _historyBusinessPageFromFrb,
  );

  Future<HistoryCut> waitChanged(HistoryCut after) => _guardedCall(
    () => history.waitChanged(after: _historyCutToFrb(after)),
    _historyCutFromFrb,
  );

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

  Future<CurrentView> snapshot(ReadDemand demand) => _guardedCall(
    () => current.snapshot(demand: _readDemandToFrb(demand)),
    _currentViewFromFrb,
  );

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
  }) => _guardedCall(
    () => current.pageCollection(
      reference: _currentCollectionRefToFrb(reference),
      continuation: continuation,
      demand: _readDemandToFrb(demand),
    ),
    _currentCollectionPageFromFrb,
  );

  Future<ContentWindow> readBody({
    required CurrentContentRef reference,
    required ContentRange range,
  }) => _guardedCall(
    () => current.readBody(
      reference: _currentContentRefToFrb(reference),
      range: _contentRangeToFrb(range),
    ),
    _contentWindowFromFrb,
  );

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

abstract class _FrbPullStreamWatch<H, T> {
  _FrbPullStreamWatch(this._entry) {
    _output = StreamController(onListen: _start, onCancel: requestClose);
  }

  final ClientAcquisition<_FrbRawPull<H, T>> _entry;
  late final StreamController<T> _output;
  Future<void>? _pumping;
  bool _started = false;
  bool _closed = false;

  Stream<T> get _stream => _output.stream;

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
            final item = await raw.next();
            if (_closed) return;
            if (item == null) break;
            _output.add(item);
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

  void requestClose() {
    if (_closed) return;
    _closed = true;
    _entry.requestClose();
  }

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

final class _FrbCurrentWatch
    extends _FrbPullStreamWatch<frb_timeline.BridgeCurrentWatch, CurrentFrame>
    implements CurrentWatch {
  _FrbCurrentWatch(super.entry);

  @override
  Stream<CurrentFrame> get frames => _stream;
}

final class _FrbCurrentBodyWatch
    extends
        _FrbPullStreamWatch<frb_timeline.BridgeCurrentBodyWatch, ContentWindow>
    implements CurrentBodyWatch {
  _FrbCurrentBodyWatch(super.entry);

  @override
  Stream<ContentWindow> get windows => _stream;
}
