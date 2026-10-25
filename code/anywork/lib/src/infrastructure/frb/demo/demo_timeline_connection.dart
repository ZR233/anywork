import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/conversation_ports.dart';
import 'package:anywork_client/resources.dart';

import '../shared/adapter_failure.dart';
import '../shared/feed_connection.dart';
import 'demo_timeline_content.dart';
import 'demo_timeline_preview.dart';

/// One demo Thread/content connection.
///
/// The shared adapter mechanics (single consumer, typed Cancelled after close,
/// close/retry join, ACK routing) are the same ones the native adapter uses; the
/// demo window below is this port's own transport delivery, so the canonical
/// Repository and the tail consumer cannot tell demo and native apart.
final class DemoTimelineConnection implements StudioTimelineConnection {
  DemoTimelineConnection({
    required DemoTimelineContent content,
    required this.threadId,
    required this.subscriptionId,
  }) : _window = _DemoTimelineWindow(
         content: content,
         threadId: threadId,
         subscriptionId: subscriptionId,
       ) {
    _feed =
        AdapterFeedConnection<StudioTimelineFeedFrame, StudioTimelineFeedFrame>(
          resource: 'demo-timeline',
          openNativeStream: _window.open,
          convert: (frame) => frame,
          failureFrame: (failure) =>
              StudioTimelineFeedFrame.failure(error: failure),
          isTerminal: (frame) => frame is! StudioTimelineFeedData,
          identity: (frame) => switch (frame) {
            StudioTimelineFeedData(
              event: StudioTimelineFeedBaseline(:final baseline),
            ) =>
              baseline.subscriptionId,
            _ => null,
          },
          acknowledgeNative: _window.acknowledge,
          requestNativeClose: _window.detach,
          closeNative: () async => _closeReport(),
          retryNativeClose: () async => _closeReport(),
          // The inner window releases its own copy and controller on detach.
          disposeNative: () {},
          mapFailure: (error) =>
              adapterFailure(error, operation: 'demo-timeline'),
        );
  }

  final String threadId;
  final String subscriptionId;
  final _DemoTimelineWindow _window;
  late final AdapterFeedConnection<
    StudioTimelineFeedFrame,
    StudioTimelineFeedFrame
  >
  _feed;

  FeedCloseReport _closeReport() => FeedCloseReport(
    feedId: subscriptionId,
    outcome: const FeedCloseOutcome.clean(),
  );

  @override
  Stream<StudioTimelineFeedFrame> get events => _feed.events;

  @override
  Future<void> ackThrough(int deliverySequence) =>
      _feed.ackThrough(deliverySequence);

  @override
  Future<StudioTimelinePage> page({String? before, int? limit}) =>
      _feed.owner.query(() => _window.page(before: before, limit: limit));

  @override
  Future<StudioTimelineDetailChunk> readDetail({
    required String itemId,
    required StudioTimelineDetailQuery query,
  }) => _feed.owner.query(() => _window.readDetail(itemId, query));

  @override
  void requestClose() => _feed.requestClose();

  @override
  Future<FeedCloseReport> close() => _feed.close();

  @override
  Future<FeedCloseReport> retryClose() => _feed.retryClose();
}

/// A trimmed canonical item with the preview it was metered into.
final class _DemoStagedItem {
  const _DemoStagedItem(this.item, this.preview);

  final ThreadItemView item;
  final DemoTimelinePreview preview;
}

/// One metered page/baseline candidate. Preview and metering fully succeed
/// before a connection commits it to its own continuity copy.
final class _DemoPageStage {
  const _DemoPageStage({
    required this.items,
    required this.before,
    required this.hasOlder,
  });

  /// Ascending canonical order; the earliest entry is the `before` boundary.
  final List<_DemoStagedItem> items;
  final String? before;
  final bool hasOlder;
}

/// The demo transport window: bounded first baseline, at most two unacked data
/// frames, one staged result, explicit resync when continuity cannot be proven.
///
/// Credits, sequence numbers and ACK discipline mirror the native bridge
/// contract (design/26 §26.2): the first data sequence is 1, the baseline takes
/// one credit, `ackThrough` only returns a contiguous prefix, and a payload that
/// cannot be metered terminates this connection with a typed failure.
final class _DemoTimelineWindow {
  _DemoTimelineWindow({
    required this.content,
    required this.threadId,
    required this.subscriptionId,
  });

  static const int _windowLimit = 2;
  static const int _pageSize = 32;

  final DemoTimelineContent content;
  final String threadId;
  final String subscriptionId;

  /// Bounded continuity copy: delivered previews plus their numeric ledgers.
  final Map<String, ThreadItemView> _delivered = {};
  final Map<String, List<StudioTimelineDetailRef>> _deliveredDetails = {};
  final Map<String, int> _deliveredBytes = {};

  /// Identities that slid out of the bounded copy: their later facts cannot be
  /// expressed as a continuous delta.
  final Set<String> _evicted = {};
  bool _evictedOverflow = false;

  /// Delivered range boundaries (ordinal, id); they only widen with delivery.
  (int, String)? _floor;
  (int, String)? _ceiling;
  int? _deliveredVersion;

  /// Unacked data sequences. Failure/Closed are control frames, not credited.
  final Set<int> _inFlight = {};
  int _lastSent = 0;
  int _ackedThrough = 0;
  bool _dirty = false;
  bool _flushScheduled = false;
  bool _terminal = false;
  bool _detached = false;
  StreamController<StudioTimelineFeedFrame>? _controller;
  void Function()? _contentListener;

  Stream<StudioTimelineFeedFrame> open() {
    final controller = StreamController<StudioTimelineFeedFrame>();
    _controller = controller;
    controller.onListen = () {
      if (_detached || _terminal) {
        unawaited(
          controller.close().then(
            (_) {},
            onError: (Object error, StackTrace stack) {},
          ),
        );
        return;
      }
      final listener = _onContentChanged;
      _contentListener = listener;
      content.addContentListener(threadId, listener);
      _emitBaseline();
    };
    controller.onCancel = detach;
    return controller.stream;
  }

  void _onContentChanged() {
    if (_detached || _terminal) return;
    _dirty = true;
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_flushScheduled || _detached || _terminal) return;
    _flushScheduled = true;
    // Coalescing is the fixed framing window for plain content: one synchronous
    // burst of changes is delivered as the single next frame it can prove.
    scheduleMicrotask(() {
      _flushScheduled = false;
      _flush();
    });
  }

  void _emitBaseline() {
    try {
      final baseline = _buildBaseline();
      _send(StudioTimelineFeedEvent.baseline(baseline: baseline));
    } on StudioFailure catch (failure) {
      _fail(failure);
    }
    _flush();
  }

  void _flush() {
    while (true) {
      if (_detached || _terminal) return;
      if (_inFlight.length >= _windowLimit) return;
      final delivered = _deliveredVersion;
      if (delivered == null || !_dirty) return;
      final version = content.versionOf(threadId);
      if (version <= delivered) {
        _dirty = false;
        return;
      }
      // Only a single provable change becomes a delta; anything crossed while
      // the window was closed must resync instead of replaying business output.
      final change = content.lastChangeOf(threadId);
      final single =
          version == delivered + 1 &&
              change != null &&
              change.version == version
          ? change
          : null;
      try {
        final expressed = single == null ? null : _express(single);
        if (expressed == null) {
          final baseline = _buildBaseline();
          _send(
            StudioTimelineFeedEvent.update(
              update: StudioTimelineResync(
                subscriptionId: subscriptionId,
                reason: StudioTimelineResyncReason.lagging,
                baseline: baseline,
              ),
            ),
          );
        } else {
          _deliveredVersion = version;
          _send(
            StudioTimelineFeedEvent.update(
              update: StudioTimelinePatch(
                subscriptionId: subscriptionId,
                from: delivered,
                to: version,
                changes: List.unmodifiable(expressed),
                priority: StudioTimelinePriority.coalesced,
              ),
            ),
          );
        }
      } on StudioFailure catch (failure) {
        _fail(failure);
        return;
      }
    }
  }

  void _send(StudioTimelineFeedEvent event) {
    final controller = _controller;
    if (_terminal || _detached || controller == null || controller.isClosed) {
      return;
    }
    _lastSent += 1;
    _inFlight.add(_lastSent);
    controller.add(
      StudioTimelineFeedData(deliverySequence: _lastSent, event: event),
    );
  }

  /// Contiguous-prefix ACK. Repeated/older acknowledgements are idempotent and
  /// an acknowledgement beyond the delivered sequence is a typed protocol error.
  Future<void> acknowledge(BigInt sequence) async {
    final value = sequence.toInt();
    if (value == 0) return;
    if (value > _lastSent) {
      throw const StudioFailure(
        code: StudioFailureCode.protocol,
        message: 'The demo Timeline ACK exceeds the delivered sequence',
        retryable: false,
        correlationId: 'demo-timeline-ack',
      );
    }
    if (value <= _ackedThrough) return;
    _ackedThrough = value;
    _inFlight.removeWhere((sent) => sent <= value);
    _flush();
  }

  void _fail(StudioFailure failure) {
    final controller = _controller;
    if (_terminal || _detached || controller == null || controller.isClosed) {
      return;
    }
    _terminal = true;
    _dirty = false;
    _releaseListener();
    try {
      controller.add(StudioTimelineFeedFrame.failure(error: failure));
    } on Object {
      // The consumer already detached; the typed failure stays with this owner.
    }
  }

  void _releaseListener() {
    final listener = _contentListener;
    _contentListener = null;
    if (listener != null) content.removeContentListener(threadId, listener);
  }

  /// Close/detach: refuse new work, drop this connection's preview copy and stop
  /// forwarding. Repeated detach is idempotent.
  void detach() {
    if (_detached) return;
    _detached = true;
    _dirty = false;
    _releaseListener();
    _delivered.clear();
    _deliveredDetails.clear();
    _deliveredBytes.clear();
    _evicted.clear();
    _floor = null;
    _ceiling = null;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      unawaited(
        controller.close().then(
          (_) {},
          onError: (Object error, StackTrace stack) {},
        ),
      );
    }
  }

  // ---- Baseline / page ----

  StudioTimelineBaseline _buildBaseline() {
    final version = content.versionOf(threadId);
    // Fully meter before committing: a candidate that fails mid-way never
    // half-publishes this connection's copy.
    final stage = _stagePage(content.itemsOf(threadId), _pageSize);
    _commit(stage, version);
    return StudioTimelineBaseline(
      subscriptionId: subscriptionId,
      version: version,
      items: List.unmodifiable([
        for (final entry in stage.items)
          _timelineItem(entry.item, entry.preview),
      ]),
      before: stage.before,
      hasOlder: stage.hasOlder,
    );
  }

  /// Replace this connection's continuity copy with one metered page. The page
  /// ceiling never exceeds the copy ceiling, so no immediate eviction is needed.
  void _commit(_DemoPageStage stage, int version) {
    _delivered.clear();
    _deliveredDetails.clear();
    _deliveredBytes.clear();
    for (final entry in stage.items) {
      _delivered[entry.item.id] = entry.preview.item;
      _deliveredDetails[entry.item.id] = entry.preview.details;
      _deliveredBytes[entry.item.id] = entry.preview.accountedBytes;
    }
    _deliveredVersion = version;
    _evicted.clear();
    _evictedOverflow = false;
    _floor = stage.items.isEmpty ? null : _keyOf(stage.items.first.item);
    _ceiling = stage.items.isEmpty ? null : _keyOf(stage.items.last.item);
  }

  /// Stateless history page: `before` is an opaque order boundary bound to this
  /// Thread. A byte-budget cut keeps its real older cursor instead of claiming
  /// EOF.
  Future<StudioTimelinePage> page({String? before, int? limit}) async {
    final size = limit ?? _pageSize;
    if (size < 1 || size > 100) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Timeline page limit must be within 1..100',
        retryable: false,
        correlationId: 'demo-timeline-page-limit',
      );
    }
    final items = content.itemsOf(threadId);
    final boundary = before == null ? null : _ordinalFromCursor(before);
    final older = boundary == null
        ? items
        : [
            for (final item in items)
              if (item.ordinal < boundary) item,
          ];
    final stage = _stagePage(older, size);
    return StudioTimelinePage(
      items: List.unmodifiable([
        for (final entry in stage.items)
          _timelineItem(entry.item, entry.preview),
      ]),
      before: stage.before,
      hasOlder: stage.hasOlder,
    );
  }

  /// Accumulate from the newest end under both ceilings. A cut page reports the
  /// earliest actually delivered item as its deeper boundary.
  _DemoPageStage _stagePage(List<ThreadItemView> older, int limit) {
    final staged = <_DemoStagedItem>[];
    var total = 0;
    for (
      var index = older.length - 1;
      index >= 0 && staged.length < limit;
      index--
    ) {
      final item = older[index];
      final preview = demoPreviewOf(item);
      if (staged.isNotEmpty &&
          total + preview.accountedBytes > demoPageLimitBytes) {
        break;
      }
      total += preview.accountedBytes;
      staged.add(_DemoStagedItem(item, preview));
    }
    final items = List<_DemoStagedItem>.unmodifiable(staged.reversed);
    final oldest = items.isEmpty ? null : items.first.item;
    return _DemoPageStage(
      items: items,
      before: oldest == null ? null : _cursor(oldest.ordinal),
      hasOlder: _hasOlderThan(oldest?.ordinal),
    );
  }

  StudioTimelineItem _timelineItem(
    ThreadItemView full,
    DemoTimelinePreview preview,
  ) => StudioTimelineItem(
    item: preview.item,
    saved: full.saved,
    lifecycle: full.executionTerminal
        ? StudioTimelineLifecycle.terminal
        : StudioTimelineLifecycle.streaming,
    omittedBytes: preview.omittedBytes,
    details: preview.details,
  );

  // ---- Delta expression ----

  /// Express one notified change as a typed delta; null means continuity cannot
  /// be proven and the caller must resync.
  List<StudioTimelineChange>? _express(DemoTimelineItemChange change) {
    final id = change.itemId;
    if (change.removed) {
      // A real removal is self-contained by identity, even when this connection
      // never delivered or already evicted it.
      _delivered.remove(id);
      _deliveredDetails.remove(id);
      _deliveredBytes.remove(id);
      _evicted.remove(id);
      return [StudioTimelineRemove(id)];
    }
    final item = change.item;
    if (item == null) return null;
    final previous = _delivered[id];
    if (previous != null) {
      final preview = demoPreviewOf(item);
      final update = _itemUpdate(
        previous,
        _deliveredDetails[id]!,
        preview,
        item,
      );
      if (update == null) return null;
      final changed =
          update.fields.isNotEmpty ||
          update.expectedRevision != update.revision ||
          previous.saved != preview.item.saved ||
          previous.executionTerminal != preview.item.executionTerminal ||
          update.itemShell != null;
      _delivered[id] = preview.item;
      _deliveredDetails[id] = preview.details;
      _deliveredBytes[id] = preview.accountedBytes;
      _prune(id);
      return changed ? [update] : const [];
    }
    final key = _keyOf(item);
    final floor = _floor;
    if (floor != null && _compareKeys(key, floor) < 0) {
      // Earlier and never delivered: no tail insertion and no cached body. A
      // later page returns that moment's authoritative value.
      if (_evicted.contains(id) || _evictedOverflow) return null;
      return const [];
    }
    final ceiling = _ceiling;
    if (ceiling != null && _compareKeys(key, ceiling) <= 0) {
      // A new identity inside the delivered range cannot be proven continuous.
      return null;
    }
    final preview = demoPreviewOf(item);
    _delivered[id] = preview.item;
    _deliveredDetails[id] = preview.details;
    _deliveredBytes[id] = preview.accountedBytes;
    _ceiling = key;
    _prune(id);
    return [StudioTimelineAdd(_timelineItem(item, preview))];
  }

  StudioTimelineUpdateItem? _itemUpdate(
    ThreadItemView previous,
    List<StudioTimelineDetailRef> previousDetails,
    DemoTimelinePreview next,
    ThreadItemView full,
  ) {
    final fields = _fieldUpdates(previous, previousDetails, next, full);
    if (fields == null) return null;
    return StudioTimelineUpdateItem(
      itemId: full.id,
      expectedRevision: previous.revision,
      revision: full.revision,
      omittedBytes: next.omittedBytes,
      saved: full.saved,
      lifecycle: full.executionTerminal
          ? StudioTimelineLifecycle.terminal
          : StudioTimelineLifecycle.streaming,
      itemShell:
          previous.state.runtimeType != next.item.state.runtimeType ||
              previous.updatedAt != full.updatedAt ||
              previous.isTerminal != full.isTerminal
          ? next.item
          : null,
      fields: fields,
    );
  }

  /// Typed field changes between two capped previews; the full item only
  /// supplies real field totals.
  ///
  /// Field existence follows the canonical field set, never the trimmed preview:
  /// a field without budget is delivered as an empty preview with its real
  /// total, and only a canonical disappearance becomes `Remove`.
  List<StudioFieldUpdateView>? _fieldUpdates(
    ThreadItemView previous,
    List<StudioTimelineDetailRef> previousDetails,
    DemoTimelinePreview next,
    ThreadItemView full,
  ) {
    final previousFields = demoTimelineFieldsOf(previous);
    final fullFields = demoTimelineFieldsOf(full);
    final previewFields = demoTimelineFieldsOf(next.item);
    final previousTotals = {
      for (final ref in previousDetails) ref.field: ref.totalBytes,
    };
    final changes = <StudioFieldUpdateView>[];
    for (final entry in fullFields.entries) {
      final field = entry.key;
      final previewText = previewFields[field] ?? '';
      final total = _byteLength(entry.value);
      final previewBytes = _byteLength(previewText);
      final previousText = previousFields[field];
      final previousTotal = previousTotals[field] ?? 0;
      if (previousText != null &&
          previewBytes < _byteLength(previousText) &&
          total >= previousTotal) {
        // The canonical body did not shrink but its preview did: that is budget
        // redistribution, which cannot be proven as a continuous delta.
        return null;
      }
      if (previousText == null) {
        changes.add(
          StudioFieldUpdateView(
            field: field,
            change: AppendThreadFieldChangeView(previewText),
            totalBytes: total,
            previewBytes: previewBytes,
          ),
        );
        continue;
      }
      if (previousText == previewText) {
        // Preview already capped while the body keeps growing: still advance the
        // per-field metadata, exactly like the native producer.
        if (previousTotal != total) {
          changes.add(
            StudioFieldUpdateView(
              field: field,
              change: const UnchangedThreadFieldChangeView(),
              totalBytes: total,
              previewBytes: previewBytes,
            ),
          );
        }
        continue;
      }
      changes.add(
        StudioFieldUpdateView(
          field: field,
          change: previewText.startsWith(previousText)
              ? AppendThreadFieldChangeView(
                  previewText.substring(previousText.length),
                )
              : ReplaceThreadFieldChangeView(previewText),
          totalBytes: total,
          previewBytes: previewBytes,
        ),
      );
    }
    for (final entry in previousFields.entries) {
      // Only a canonical field disappearance is a Remove.
      if (fullFields.containsKey(entry.key)) continue;
      changes.add(
        StudioFieldUpdateView(
          field: entry.key,
          change: const RemoveThreadFieldChangeView(),
          totalBytes: 0,
          previewBytes: 0,
        ),
      );
    }
    return changes;
  }

  /// Bounded copy: 100 items AND 8 MiB, keeping the newest delivered previews.
  /// Eviction is not a removal notification.
  void _prune(String newest) {
    while (_delivered.length > demoContinuityItemLimit ||
        _deliveredBytesTotal() > demoContinuityByteLimit) {
      if (_delivered.length <= 1) break;
      final oldest = _delivered.keys
          .where((id) => id != newest)
          .reduce(
            (left, right) =>
                _compareKeys(
                      _keyOf(_delivered[left]!),
                      _keyOf(_delivered[right]!),
                    ) <=
                    0
                ? left
                : right,
          );
      _delivered.remove(oldest);
      _deliveredDetails.remove(oldest);
      _deliveredBytes.remove(oldest);
      if (_evicted.length >= demoContinuityItemLimit) {
        _evicted.remove(_evicted.first);
        _evictedOverflow = true;
      }
      _evicted.add(oldest);
    }
    if (_delivered.isEmpty) return;
    _floor = _delivered.values
        .map(_keyOf)
        .reduce((left, right) => _compareKeys(left, right) <= 0 ? left : right);
    _ceiling = _delivered.values
        .map(_keyOf)
        .reduce((left, right) => _compareKeys(left, right) >= 0 ? left : right);
  }

  int _deliveredBytesTotal() {
    var total = 0;
    for (final bytes in _deliveredBytes.values) {
      total += bytes;
    }
    return total;
  }

  // ---- Detail reads ----

  /// Read one field body by item/field/revision; the continuation is an opaque
  /// UTF-8 byte cursor bound to Thread, item, field and revision.
  Future<StudioTimelineDetailChunk> readDetail(
    String itemId,
    StudioTimelineDetailQuery query,
  ) async {
    final maxBytes = query.maxBytes ?? demoDefaultDetailBytes;
    if (maxBytes < demoMinDetailBytes || maxBytes > demoMaxDetailBytes) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Timeline detail block size must be within 4..262144 bytes',
        retryable: false,
        correlationId: 'demo-timeline-detail-block',
      );
    }
    ThreadItemView? item;
    for (final entry in content.itemsOf(threadId)) {
      if (entry.id == itemId) {
        item = entry;
        break;
      }
    }
    if (item == null) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'The timeline item is no longer available',
        retryable: false,
        correlationId: 'demo-timeline-detail-not-found',
      );
    }
    if (item.revision != query.revision) {
      throw const StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'The timeline item revision changed',
        retryable: false,
        correlationId: 'demo-timeline-detail-stale',
      );
    }
    final body = demoTimelineFieldText(item, query.field);
    if (body == null) {
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'The timeline field is not available',
        retryable: false,
        correlationId: 'demo-timeline-detail-field',
      );
    }
    final bytes = utf8.encode(body);
    var start = 0;
    final continuation = query.continuation;
    if (continuation != null) {
      final parsed = _parseDetailContinuation(continuation);
      // The cursor is bound to Thread, item, field and revision: reusing it
      // across any of them is rejected instead of splicing two bodies.
      if (parsed.threadId != threadId ||
          parsed.itemId != itemId ||
          parsed.field != query.field) {
        throw _invalidDetailCursor();
      }
      if (parsed.revision != query.revision) {
        throw const StudioFailure(
          code: StudioFailureCode.staleRevision,
          message: 'The timeline detail cursor belongs to another revision',
          retryable: false,
          correlationId: 'demo-timeline-detail-cursor-revision',
        );
      }
      if (parsed.offset > bytes.length) throw _invalidDetailCursor();
      if (parsed.offset < bytes.length &&
          (bytes[parsed.offset] & 0xC0) == 0x80) {
        throw _invalidDetailCursor();
      }
      start = parsed.offset;
    }
    var end = start + maxBytes;
    if (end > bytes.length) end = bytes.length;
    if (end < bytes.length) {
      // Only cut on a legal UTF-8 boundary; maxBytes >= 4 guarantees progress.
      while (end > start && (bytes[end] & 0xC0) == 0x80) {
        end -= 1;
      }
      if (end == start) throw _invalidDetailCursor();
    }
    final String text;
    try {
      text = utf8.decode(bytes.sublist(start, end));
    } on FormatException {
      throw _invalidDetailCursor();
    }
    return StudioTimelineDetailChunk(
      itemId: item.id,
      field: query.field,
      revision: item.revision,
      text: text,
      totalBytes: bytes.length,
      continuation: end < bytes.length
          ? _detailContinuationToken(
              itemId: item.id,
              field: query.field,
              revision: item.revision,
              offset: end,
            )
          : null,
    );
  }

  StudioFailure _invalidDetailCursor() => const StudioFailure(
    code: StudioFailureCode.invalidArgument,
    message: 'The timeline detail cursor is invalid',
    retryable: false,
    correlationId: 'demo-timeline-detail-cursor',
  );

  /// Opaque continuation: versioned JSON + base64url, bound to Thread, item,
  /// field, revision and a legal UTF-8 byte offset.
  String _detailContinuationToken({
    required String itemId,
    required ThreadContentFieldView field,
    required int revision,
    required int offset,
  }) {
    final payload = <String, Object?>{
      'v': 1,
      't': threadId,
      'i': itemId,
      'f': _fieldToWire(field),
      'r': revision,
      'o': offset,
    };
    return base64Url.encode(utf8.encode(jsonEncode(payload)));
  }

  ({
    String threadId,
    String itemId,
    ThreadContentFieldView field,
    int revision,
    int offset,
  })
  _parseDetailContinuation(String token) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(base64Url.decode(token)));
    } on Object {
      throw _invalidDetailCursor();
    }
    if (decoded is! Map<String, Object?>) throw _invalidDetailCursor();
    final version = decoded['v'];
    final threadId = decoded['t'];
    final itemId = decoded['i'];
    final revision = decoded['r'];
    final offset = decoded['o'];
    final field = _fieldFromWire(decoded['f']);
    if (version != 1 ||
        threadId is! String ||
        itemId is! String ||
        revision is! int ||
        offset is! int ||
        revision < 0 ||
        offset < 0 ||
        field == null) {
      throw _invalidDetailCursor();
    }
    return (
      threadId: threadId,
      itemId: itemId,
      field: field,
      revision: revision,
      offset: offset,
    );
  }

  Map<String, Object?> _fieldToWire(ThreadContentFieldView field) =>
      switch (field) {
        ThreadTextFieldView() => {'k': 'text'},
        ThreadThinkingSummaryFieldView(:final chunkIndex) => {
          'k': 'summary',
          'i': chunkIndex,
        },
        ThreadThinkingContentFieldView(:final chunkIndex) => {
          'k': 'content',
          'i': chunkIndex,
        },
        ThreadToolArgumentsFieldView() => {'k': 'args'},
        ThreadToolResultFieldView() => {'k': 'result'},
        ThreadToolOutputArtifactsFieldView() => {'k': 'artifacts'},
        ThreadRawPayloadFieldView(:final payloadIndex) => {
          'k': 'raw',
          'i': payloadIndex,
        },
        ThreadToolUserInputFieldView(:final questionIndex, :final part) => {
          'k': 'input',
          'q': questionIndex,
          'p': _partToWire(part),
        },
      };

  Map<String, Object?> _partToWire(ThreadUserInputFieldPartView part) =>
      switch (part) {
        ThreadUserInputHeaderFieldPartView() => {'k': 'header'},
        ThreadUserInputQuestionFieldPartView() => {'k': 'question'},
        ThreadUserInputAnswerFieldPartView(:final answerIndex) => {
          'k': 'answer',
          'i': answerIndex,
        },
        ThreadUserInputOptionLabelFieldPartView(:final optionIndex) => {
          'k': 'label',
          'i': optionIndex,
        },
        ThreadUserInputOptionDescriptionFieldPartView(:final optionIndex) => {
          'k': 'description',
          'i': optionIndex,
        },
      };

  ThreadContentFieldView? _fieldFromWire(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final index = value['i'];
    switch (value['k']) {
      case 'text':
        return const ThreadTextFieldView();
      case 'summary':
        return index is int ? ThreadThinkingSummaryFieldView(index) : null;
      case 'content':
        return index is int ? ThreadThinkingContentFieldView(index) : null;
      case 'args':
        return const ThreadToolArgumentsFieldView();
      case 'result':
        return const ThreadToolResultFieldView();
      case 'artifacts':
        return const ThreadToolOutputArtifactsFieldView();
      case 'raw':
        return index is int ? ThreadRawPayloadFieldView(index) : null;
      case 'input':
        final questionIndex = value['q'];
        final part = _partFromWire(value['p']);
        if (questionIndex is! int || part == null) return null;
        return ThreadToolUserInputFieldView(
          questionIndex: questionIndex,
          part: part,
        );
      default:
        return null;
    }
  }

  ThreadUserInputFieldPartView? _partFromWire(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final index = value['i'];
    switch (value['k']) {
      case 'header':
        return const ThreadUserInputHeaderFieldPartView();
      case 'question':
        return const ThreadUserInputQuestionFieldPartView();
      case 'answer':
        return index is int ? ThreadUserInputAnswerFieldPartView(index) : null;
      case 'label':
        return index is int
            ? ThreadUserInputOptionLabelFieldPartView(index)
            : null;
      case 'description':
        return index is int
            ? ThreadUserInputOptionDescriptionFieldPartView(index)
            : null;
      default:
        return null;
    }
  }

  // ---- Order helpers ----

  bool _hasOlderThan(int? ordinal) {
    if (ordinal == null) return false;
    return content.itemsOf(threadId).any((item) => item.ordinal < ordinal);
  }

  String _cursor(int ordinal) =>
      'dtl1.${base64Url.encode(utf8.encode(threadId))}.$ordinal';

  int _ordinalFromCursor(String token) {
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != 'dtl1') throw _invalidPageCursor();
    String decoded;
    try {
      decoded = utf8.decode(base64Url.decode(parts[1]));
    } on Object {
      throw _invalidPageCursor();
    }
    final ordinal = int.tryParse(parts[2]);
    if (decoded != threadId || ordinal == null || ordinal < 0) {
      throw _invalidPageCursor();
    }
    return ordinal;
  }

  StudioFailure _invalidPageCursor() => const StudioFailure(
    code: StudioFailureCode.invalidArgument,
    message: 'The timeline page cursor is invalid',
    retryable: false,
    correlationId: 'demo-timeline-page-cursor',
  );

  static (int, String) _keyOf(ThreadItemView item) => (item.ordinal, item.id);

  static int _compareKeys((int, String) left, (int, String) right) {
    final byOrdinal = left.$1.compareTo(right.$1);
    return byOrdinal != 0 ? byOrdinal : left.$2.compareTo(right.$2);
  }

  int _byteLength(String value) => utf8.encode(value).length;
}
