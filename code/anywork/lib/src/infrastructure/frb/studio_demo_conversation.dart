part of 'studio_api.dart';

/// Demo facts use the same typed descriptor/field shape as the public read model.
/// Full field text lives only in Demo's authoritative item table; feed copies are bounded previews.
typedef _DemoContent = ({
  ConversationDescriptor descriptor,
  Map<ThreadContentFieldView, String> fields,
});

_DemoContent _demoText({
  required ThreadTextChannel channel,
  required String text,
  required List<ThreadAttachmentView> attachments,
  required ThreadContentLifecycleView lifecycle,
}) => (
  descriptor: ConversationTextDescriptor(
    channel: channel,
    attachments: attachments,
    lifecycle: lifecycle,
  ),
  fields: {const ThreadTextFieldView(): text},
);
_DemoContent _demoThinking({
  required List<String> summary,
  required List<String> content,
  required ThreadContentLifecycleView lifecycle,
}) => (
  descriptor: ConversationThinkingDescriptor(lifecycle: lifecycle),
  fields: {
    for (var i = 0; i < summary.length; i++)
      ThreadThinkingSummaryFieldView(i): summary[i],
    for (var i = 0; i < content.length; i++)
      ThreadThinkingContentFieldView(i): content[i],
  },
);
_DemoContent _demoTool({
  required ConversationToolInvocation invocation,
  required ConversationToolState lifecycle,
  String arguments = '',
  String result = '',
}) => (
  descriptor: ConversationToolDescriptor(
    invocation: invocation,
    state: lifecycle,
  ),
  fields: {
    const ThreadToolArgumentsFieldView(): arguments,
    if (lifecycle is ConversationToolRunning || lifecycle.isTerminal)
      const ThreadToolResultFieldView(): result,
  },
);
_DemoContent _demoTurn(StudioTurnState state, {String? inputId}) => (
  descriptor: ConversationTurnDescriptor(
    ThreadTurnItemStateView(state, inputId: inputId),
  ),
  fields: {},
);

bool _demoTerminal(ConversationDescriptor descriptor) => switch (descriptor) {
  ConversationTextDescriptor(:final lifecycle) ||
  ConversationThinkingDescriptor(:final lifecycle) => lifecycle.isTerminal,
  ConversationToolDescriptor(:final state) => state.isTerminal,
  ConversationTurnDescriptor(:final value) => !value.state.isBusy,
  ConversationAgentDescriptor(:final value) => switch (value.lifecycle) {
    QueuedThreadAgentView() || RunningThreadAgentView() => false,
    SucceededThreadAgentView() ||
    DeniedThreadAgentView() ||
    CancelledThreadAgentView() ||
    FailedThreadAgentView() => true,
  },
  ConversationInferenceDescriptor(:final value) => switch (value.lifecycle) {
    RunningThreadInferenceView() => false,
    CompletedThreadInferenceView() ||
    FailedThreadInferenceView() ||
    CancelledThreadInferenceView() => true,
  },
  ConversationRawDescriptor() ||
  ConversationSkillDescriptor() ||
  ConversationFileDescriptor() ||
  ConversationContextCompactionDescriptor() => true,
};

ConversationItem _demoItem({
  required String id,
  required String threadId,
  required String turnId,
  required int ordinal,
  required int revision,
  required DateTime createdAt,
  required DateTime updatedAt,
  required _DemoContent content,
  bool saved = true,
}) => ConversationItem(
  header: ConversationItemHeader(
    id: id,
    threadId: threadId,
    turnId: turnId,
    ordinal: ordinal,
    createdAt: createdAt,
    updatedAt: updatedAt,
  ),
  revision: revision,
  descriptor: content.descriptor,
  source: const ConversationContentSource(),
  saved: saved,
  lifecycle: _demoTerminal(content.descriptor)
      ? ConversationLifecycle.terminal
      : ConversationLifecycle.streaming,
  fields: List.unmodifiable(
    content.fields.entries.map(
      (entry) => ConversationFieldPreview(
        field: entry.key,
        text: entry.value,
        totalBytes: utf8.encode(entry.value).length,
      ),
    ),
  ),
);
ConversationItem _demoRevise(
  ConversationItem item, {
  int? revision,
  DateTime? updatedAt,
  _DemoContent? content,
  Map<ThreadContentFieldView, String>? fields,
  bool? saved,
}) => ConversationItem(
  header: ConversationItemHeader(
    id: item.id,
    threadId: item.header.threadId,
    turnId: item.header.turnId,
    ordinal: item.header.ordinal,
    createdAt: item.header.createdAt,
    updatedAt: updatedAt ?? item.header.updatedAt,
  ),
  revision: revision ?? item.revision,
  descriptor: content?.descriptor ?? item.descriptor,
  source: item.source,
  saved: saved ?? item.saved,
  lifecycle: content == null
      ? item.lifecycle
      : _demoTerminal(content.descriptor)
      ? ConversationLifecycle.terminal
      : ConversationLifecycle.streaming,
  fields: fields == null && content == null
      ? item.fields
      : List.unmodifiable(
          (fields ?? content!.fields).entries.map(
            (entry) => ConversationFieldPreview(
              field: entry.key,
              text: entry.value,
              totalBytes: utf8.encode(entry.value).length,
            ),
          ),
        ),
);

final class _DemoConversationFeed implements ConversationFeed {
  _DemoConversationFeed(this._api, this.threadId)
    : subscriptionId = 'demo-${newStudioCorrelationId()}';
  final DemoStudioTransport _api;
  @override
  final String threadId;
  @override
  final String subscriptionId;
  String get _threadId => threadId;
  static const _pageSize = 32;
  static const _itemPreviewLimitBytes = 256 * 1024;
  static const _pageLimitBytes = 2 * 1024 * 1024;
  static const _continuityLimitBytes = 8 * 1024 * 1024;
  static const _bodyPreviewBytes = 32 * 1024;
  static const _toolPreviewBytes = 4 * 1024;
  static const _defaultDetailBytes = 64 * 1024;
  static const _minDetailBytes = 4;
  static const _maxDetailBytes = 256 * 1024;
  final Map<String, ConversationItem> _delivered = {};
  final Map<String, int> _deliveredBytes = {};
  final Set<String> _evicted = {};
  bool _evictedOverflow = false;
  int? _deliveredVersion;
  // 已覆盖顺序区间独立于预览缓存；Remove 与预算淘汰都不能擦除连续性证据。
  (int, String)? _coveredFloor;
  (int, String)? _coveredCeiling;
  int _sent = 0;
  int _acked = 0;
  bool _closed = false;
  bool _claimed = false;
  bool _started = false;
  bool _terminal = false;
  bool _pendingState = true;
  bool _pendingContent = true;
  Future<void>? _closing;
  late final StreamController<ConversationFrame> _controller = StreamController(
    onListen: _start,
    onCancel: () {
      requestClose();
      return close();
    },
  );
  List<ConversationItem> get _items => _api._itemsOf(threadId);
  int get _version => _api._contentVersionOf(threadId);
  bool get _credit => _sent - _acked < 2;
  static (int, String) _keyOf(ConversationItem value) =>
      (value.header.ordinal, value.id);
  static int _compareKeys((int, String) a, (int, String) b) {
    final n = a.$1.compareTo(b.$1);
    return n == 0 ? a.$2.compareTo(b.$2) : n;
  }

  @override
  Stream<ConversationFrame> get events {
    if (_closed) throw _conversationClosedFailure;
    if (_claimed) {
      throw const StudioFailure(
        code: StudioFailureCode.conflict,
        message: 'Conversation events already have a consumer',
        retryable: false,
        correlationId: 'demo-conversation-consumer',
      );
    }
    _claimed = true;
    return _controller.stream;
  }

  void _start() {
    if (_closed || _api._runtimeExiting) {
      requestClose();
      unawaited(_controller.close());
      return;
    }
    _started = true;
    (_api._conversationFeeds[threadId] ??= {}).add(this);
    _flush(); // registration and both captured baselines are in one synchronous publication boundary
  }

  void _send(ConversationEvent event, {bool terminal = false}) {
    if (!_started || _terminal) return;
    if (!terminal) {
      if (!_credit) throw StateError('Demo delivery credit exhausted');
      _sent++;
    }
    _controller.add(
      ConversationFrame(
        threadId: threadId,
        subscriptionId: subscriptionId,
        deliverySequence: _sent,
        event: event,
      ),
    );
    if (terminal) _terminal = true;
  }

  void _flush() {
    if (_closed || !_started) return;
    try {
      if (_pendingState && _credit) {
        _pendingState = false;
        _send(
          ConversationStateEvent(
            frame: ThreadSnapshotFrame(
              workspace: _api._snapshotOf(_api._demoWorkspace(threadId)),
            ),
          ),
        );
      }
      if (_pendingContent && _credit) {
        _pendingContent = false;
        if (_deliveredVersion == null) {
          _send(ConversationBaselineEvent(baseline: _baseline()));
        } else {
          _send(
            ConversationUpdateEvent(
              update: ConversationResync(
                subscriptionId: subscriptionId,
                reason: ConversationResyncReason.lagging,
                baseline: _baseline(),
              ),
            ),
          );
        }
      }
    } catch (error) {
      _fail(error);
    }
  }

  void _stateChanged(ThreadStreamFrame frame) {
    if (_closed || !_started) return;
    if (!_credit || _pendingState) {
      _pendingState = true;
      return;
    }
    _send(ConversationStateEvent(frame: frame));
  }

  void _contentChanged(_DemoItemChange change) {
    if (_closed || !_started) return;
    if (!_credit || _pendingContent || _deliveredVersion == null) {
      _pendingContent = true;
      return;
    }
    try {
      final from = _deliveredVersion!;
      final changes = change.version == from + 1 ? _express(change) : null;
      if (changes == null) {
        _send(
          ConversationUpdateEvent(
            update: ConversationResync(
              subscriptionId: subscriptionId,
              reason: ConversationResyncReason.lagging,
              baseline: _baseline(),
            ),
          ),
        );
      } else {
        _deliveredVersion = change.version;
        _send(
          ConversationUpdateEvent(
            update: ConversationPatch(
              subscriptionId: subscriptionId,
              from: from,
              to: change.version,
              changes: List.unmodifiable(changes),
              priority: ConversationPriority.coalesced,
            ),
          ),
        );
      }
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    _send(
      ConversationFailureEvent(failure: _studioFailure(error) as StudioFailure),
      terminal: true,
    );
    requestClose();
  }

  @override
  Future<void> acknowledge(int deliverySequence) async {
    if (_closed) throw _conversationClosedFailure;
    if (deliverySequence < 0 || deliverySequence > _sent) {
      throw _conversationQueryFailure;
    }
    if (deliverySequence <= _acked) return;
    _acked = deliverySequence;
    _flush();
  }

  ConversationBaseline _baseline() {
    final stage = _stagePage(_items, _pageSize);
    _delivered.clear();
    _deliveredBytes.clear();
    _evicted.clear();
    _evictedOverflow = false;
    _coveredFloor = null;
    _coveredCeiling = null;
    for (final entry in stage.items) {
      _delivered[entry.item.id] = entry.item;
      _deliveredBytes[entry.item.id] = entry.bytes;
      _cover(_keyOf(entry.item));
    }
    _deliveredVersion = _version;
    return ConversationBaseline(
      subscriptionId: subscriptionId,
      version: _version,
      items: List.unmodifiable(stage.items.map((entry) => entry.item)),
      before: stage.before,
      hasOlder: stage.hasOlder,
    );
  }

  List<ConversationChange>? _express(_DemoItemChange change) {
    final id = change.itemId;
    if (change.removed) {
      _delivered.remove(id);
      _deliveredBytes.remove(id);
      _evicted.remove(id);
      return [ConversationRemove(id)];
    }
    final full = change.item;
    if (full == null) return null;
    final preview = _previewOf(full);
    final previous = _delivered[id];
    if (previous == null) {
      final floor = _coveredFloor;
      final ceiling = _coveredCeiling;
      if (floor != null && ceiling != null) {
        if (_compareKeys(_keyOf(full), floor) < 0) {
          return _evicted.contains(id) || _evictedOverflow ? null : const [];
        }
        if (_compareKeys(_keyOf(full), ceiling) <= 0) return null;
      }
      _remember(preview);
      return [ConversationAdd(preview.item)];
    }
    final updates = <ConversationFieldUpdate>[];
    final oldFields = {for (final f in previous.fields) f.field: f};
    for (final f in preview.item.fields) {
      final old = oldFields.remove(f.field);
      if (old != null &&
          f.previewBytes < old.previewBytes &&
          f.totalBytes >= old.totalBytes) {
        return null;
      }
      if (old != null && f.text == old.text && f.totalBytes == old.totalBytes) {
        continue;
      }
      updates.add(
        ConversationFieldUpdate(
          field: f.field,
          change: old == null
              ? ReplaceThreadFieldChangeView(f.text)
              : f.text == old.text
              ? const UnchangedThreadFieldChangeView()
              : f.text.startsWith(old.text)
              ? AppendThreadFieldChangeView(f.text.substring(old.text.length))
              : ReplaceThreadFieldChangeView(f.text),
          totalBytes: f.totalBytes,
          previewBytes: f.previewBytes,
        ),
      );
    }
    for (final f in oldFields.keys) {
      updates.add(
        ConversationFieldUpdate(
          field: f,
          change: const RemoveThreadFieldChangeView(),
          totalBytes: 0,
          previewBytes: 0,
        ),
      );
    }
    _remember(preview);
    return [
      ConversationUpdateItem(
        itemId: id,
        expectedRevision: previous.revision,
        revision: full.revision,
        saved: full.saved,
        lifecycle: full.lifecycle,
        header: full.header,
        descriptor: full.descriptor,
        fields: List.unmodifiable(updates),
      ),
    ];
  }

  void _remember(({ConversationItem item, int bytes}) preview) {
    _cover(_keyOf(preview.item));
    _delivered[preview.item.id] = preview.item;
    _deliveredBytes[preview.item.id] = preview.bytes;
    while (_delivered.length > 100 ||
        _deliveredBytes.values.fold(0, (a, b) => a + b) >
            _continuityLimitBytes) {
      final oldest = _delivered.values
          .reduce((a, b) => _compareKeys(_keyOf(a), _keyOf(b)) < 0 ? a : b)
          .id;
      _delivered.remove(oldest);
      _deliveredBytes.remove(oldest);
      if (_evicted.length >= 100) {
        _evicted.remove(_evicted.first);
        _evictedOverflow = true;
      }
      _evicted.add(oldest);
    }
  }

  void _cover((int, String) key) {
    if (_coveredFloor == null || _compareKeys(key, _coveredFloor!) < 0) {
      _coveredFloor = key;
    }
    if (_coveredCeiling == null || _compareKeys(key, _coveredCeiling!) > 0) {
      _coveredCeiling = key;
    }
  }

  ({ConversationItem item, int bytes}) _previewOf(ConversationItem full) {
    final structure = _demoStructureBytes(full);
    if (structure > _itemPreviewLimitBytes) throw _timelineBudgetExceeded();
    var remaining = _itemPreviewLimitBytes - structure;
    if (remaining > _bodyPreviewBytes) remaining = _bodyPreviewBytes;
    final protected = <ThreadContentFieldView>{
      for (final field in full.fields)
        if (_demoPlanMarker(full, field)) field.field,
    };
    final reserved = full.fields
        .where((field) => protected.contains(field.field))
        .fold(0, (sum, field) => sum + field.previewBytes);
    if (reserved > remaining) throw _timelineBudgetExceeded();
    remaining -= reserved;
    final fields = <ConversationFieldPreview>[];
    var kept = 0;
    for (final f in full.fields) {
      var budget = remaining;
      if ((f.field is ThreadToolArgumentsFieldView ||
              f.field is ThreadToolResultFieldView) &&
          budget > _toolPreviewBytes) {
        budget = _toolPreviewBytes;
      }
      final preserved = protected.contains(f.field);
      final text = preserved ? f.text : _capDemoText(f.text, budget);
      final bytes = utf8.encode(text).length;
      if (!preserved) remaining -= bytes;
      kept += bytes;
      fields.add(
        ConversationFieldPreview(
          field: f.field,
          text: text,
          totalBytes: f.totalBytes,
        ),
      );
    }
    return (
      item: ConversationItem(
        header: full.header,
        revision: full.revision,
        descriptor: full.descriptor,
        source: full.source,
        saved: full.saved,
        lifecycle: full.lifecycle,
        fields: List.unmodifiable(fields),
      ),
      bytes: structure + kept,
    );
  }

  ({
    List<({ConversationItem item, int bytes})> items,
    String? before,
    bool hasOlder,
  })
  _stagePage(List<ConversationItem> older, int limit) {
    final staged = <({ConversationItem item, int bytes})>[];
    var total = 0;
    for (var i = older.length - 1; i >= 0 && staged.length < limit; i--) {
      final preview = _previewOf(older[i]);
      if (staged.isNotEmpty && total + preview.bytes > _pageLimitBytes) break;
      staged.add(preview);
      total += preview.bytes;
    }
    final items = List<({ConversationItem item, int bytes})>.unmodifiable(
      staged.reversed,
    );
    final oldest = items.isEmpty ? null : items.first.item;
    final hasOlder =
        oldest != null &&
        _items.any((item) => _compareKeys(_keyOf(item), _keyOf(oldest)) < 0);
    return (
      items: items,
      before: hasOlder ? _cursor(_keyOf(oldest)) : null,
      hasOlder: hasOlder,
    );
  }

  StudioFailure _cancelled() => _conversationClosedFailure;
  String? _fieldText(ConversationItem item, ThreadContentFieldView field) =>
      item.fieldFor(field)?.text;
  @override
  void requestClose() {
    if (_closed) return;
    _send(const ConversationClosedEvent(), terminal: true);
    _closed = true;
    _api._conversationFeeds[threadId]?.remove(this);
    if (_api._conversationFeeds[threadId]?.isEmpty ?? false) {
      _api._conversationFeeds.remove(threadId);
    }
    _delivered.clear();
    _deliveredBytes.clear();
    _evicted.clear();
    if (_claimed) unawaited(_controller.close());
  }

  @override
  Future<void> close() => _closing ??= Future<void>.sync(() {
    requestClose();
    // Demo 没有后台发送任务或在途异步读取。public stream.done 属于 consumer，
    // 未监听/暂停的 consumer 不能成为 producer 真实关闭的等待前置条件。
    _api._ownedConversationFeeds.remove(this);
  });

  /// 无状态历史页：`before` 是绑定 Thread 的不透明顺序边界。
  @override
  Future<ConversationPage> page({String? before, int? limit}) async {
    if (_closed) throw _cancelled();
    final size = limit ?? _pageSize;
    if (size < 1 || size > 100) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Timeline page limit must be within 1..100',
        retryable: false,
        correlationId: 'demo-timeline-page-limit',
      );
    }
    final items = _items;
    final boundary = before == null ? null : _keyFromCursor(before);
    final older = boundary == null
        ? items
        : items
              .where((item) => _compareKeys(_keyOf(item), boundary) < 0)
              .toList(growable: false);
    // 页是自包含查询：与首帧/重同步基线使用同一份总量与截页规则。
    final stage = _stagePage(older, size);
    return ConversationPage(
      items: List.unmodifiable([for (final entry in stage.items) entry.item]),
      before: stage.before,
      hasOlder: stage.hasOlder,
    );
  }

  /// 按 item/field/revision 读取完整正文；continuation 是不透明的 UTF-8 字节游标。
  @override
  Future<ConversationDetailChunk> readDetail({
    required String itemId,
    required ConversationDetailQuery query,
  }) async {
    if (_closed) throw _cancelled();
    _validateConversationUnsigned(query.revision);
    _validateConversationField(query.field);
    final maxBytes = query.maxBytes ?? _defaultDetailBytes;
    if (maxBytes < _minDetailBytes || maxBytes > _maxDetailBytes) {
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'Timeline detail block size must be within 4..262144 bytes',
        retryable: false,
        correlationId: 'demo-timeline-detail-block',
      );
    }
    final item = _items.where((entry) => entry.id == itemId).firstOrNull;
    if (item == null) {
      throw StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'The timeline item is no longer available',
        retryable: false,
        correlationId: 'demo-timeline-detail-not-found',
      );
    }
    if (item.revision != query.revision) {
      throw StudioFailure(
        code: StudioFailureCode.staleRevision,
        message: 'The timeline item revision changed',
        retryable: false,
        correlationId: 'demo-timeline-detail-stale',
      );
    }
    final body = _fieldText(item, query.field);
    if (body == null) {
      throw StudioFailure(
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
      // continuation 绑定 Thread、item、字段与 revision：跨 scope 复用一律拒绝。
      if (parsed.threadId != _threadId ||
          parsed.itemId != itemId ||
          parsed.field != query.field) {
        throw _invalidDetailCursor();
      }
      if (parsed.revision != query.revision) {
        throw const StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message: 'The timeline detail cursor belongs to another revision',
          retryable: false,
          correlationId: 'demo-timeline-detail-cursor-revision',
        );
      }
      if (parsed.offset > bytes.length) throw _invalidDetailCursor();
      // offset 必须落在合法 UTF-8 起始字节上：落在续字节上会让后续 decode 泄 FormatException。
      if (parsed.offset < bytes.length &&
          (bytes[parsed.offset] & 0xC0) == 0x80) {
        throw _invalidDetailCursor();
      }
      start = parsed.offset;
    }
    var end = start + maxBytes;
    if (end > bytes.length) end = bytes.length;
    if (end < bytes.length) {
      // 只在合法 UTF-8 边界切块：不跨多字节字符（maxBytes ≥ 4 保证至少推进一个码点）。
      while (end > start && (bytes[end] & 0xC0) == 0x80) {
        end -= 1;
      }
      if (end == start) throw _invalidDetailCursor();
    }
    final String text;
    try {
      text = utf8.decode(bytes.sublist(start, end));
    } on FormatException {
      // 任何损坏的游标/边界都统一成 typed invalidArgument，不把解码异常泄给上层。
      throw _invalidDetailCursor();
    }
    return ConversationDetailChunk(
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

  /// 不透明 continuation：版本化 JSON + base64url，绑定 Thread/item/field/revision 与
  /// 合法 UTF-8 字节偏移。字段用一个私有 typed 编码表达（Dart record 不是 JSON 可直接
  /// 编码的对象，也不能拿 `toString` 当稳定 codec）。
  String _detailContinuationToken({
    required String itemId,
    required ThreadContentFieldView field,
    required int revision,
    required int offset,
  }) {
    final payload = <String, Object?>{
      'v': 1,
      't': _threadId,
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
    } catch (_) {
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

  /// 字段身份 → 完整正文（demo 只有这些 typed 字段域）。

  String _cursor((int, String) key) =>
      'dc2.${base64Url.encode(utf8.encode(jsonEncode([threadId, key.$1, key.$2])))}';
  (int, String) _keyFromCursor(String token) {
    try {
      if (!token.startsWith('dc2.')) throw _conversationQueryFailure;
      final data = jsonDecode(
        utf8.decode(base64Url.decode(token.substring(4))),
      );
      if (data is! List ||
          data.length != 3 ||
          data[0] != threadId ||
          data[1] is! int ||
          data[1] < 0 ||
          data[2] is! String) {
        throw _conversationQueryFailure;
      }
      return (data[1] as int, data[2] as String);
    } catch (_) {
      throw _conversationQueryFailure;
    }
  }
}

String _capDemoText(String value, int budget) {
  final bytes = utf8.encode(value);
  if (bytes.length <= budget) return value;
  var end = budget;
  while (end > 0 && (bytes[end] & 0xc0) == 0x80) {
    end--;
  }
  return utf8.decode(bytes.sublist(0, end));
}

StudioFailure _timelineBudgetExceeded() => const StudioFailure(
  code: StudioFailureCode.overloaded,
  message: 'The conversation item cannot fit the preview budget',
  retryable: false,
  correlationId: 'demo-conversation-budget',
);

// Deterministic admission estimate for Demo's own typed representation, not Rust meta/wire bytes.
int _demoStructureBytes(ConversationItem item) {
  int text(String? value) => value == null ? 0 : 8 + utf8.encode(value).length;
  int attachments(List<ThreadAttachmentView> values) => values.fold(
    16,
    (n, v) => n + 48 + text(v.id) + text(v.filename) + text(v.mediaType),
  );
  int lifecycle(ThreadContentLifecycleView value) => switch (value) {
    StreamingThreadContentView() || CompletedThreadContentView() => 16,
    FailedThreadContentView(:final error) => 16 + text(error),
    CancelledThreadContentView(:final reason) => 16 + text(reason),
  };
  int output(ConversationToolOutputDescriptor? value) =>
      value == null ? 0 : 16 + attachments(value.attachments);
  var n =
      128 +
      text(item.id) +
      text(item.header.threadId) +
      text(item.header.turnId) +
      item.fields.length * 40;
  n += switch (item.source) {
    ConversationContentSource() => 8,
    ConversationRecoverySource(:final attemptId) => 16 + text(attemptId),
  };
  switch (item.descriptor) {
    case ConversationTextDescriptor(:final attachments, lifecycle: final state):
      n += attachments.length * 16 + lifecycle(state);
      n += _demoAttachmentBytes(attachments);
    case ConversationThinkingDescriptor(lifecycle: final state):
      n += lifecycle(state);
    case ConversationRawDescriptor(:final payloads, :final notice):
      n += text(notice) + payloads.fold(16, (a, p) => a + 24 + text(p.format));
    case ConversationToolDescriptor(
      :final invocation,
      :final state,
      :final userInput,
      :final wait,
    ):
      n +=
          text(invocation.toolCallId) +
          text(invocation.callId) +
          text(invocation.providerItemId) +
          text(invocation.name) +
          text(invocation.workingDirectory) +
          text(invocation.taskId);
      n += switch (state) {
        ConversationToolQueued() ||
        ConversationToolCancelling() ||
        ConversationToolStarted() ||
        ConversationToolStreaming() ||
        ConversationToolAwaitingApproval() ||
        ConversationToolApproved() ||
        ConversationToolRunning() => 16,
        ConversationToolInterrupted(:final reason) ||
        ConversationToolDenied(:final reason) ||
        ConversationToolCancelled(:final reason) => 24 + text(reason),
        ConversationToolSucceeded(output: final value) => 24 + output(value),
        ConversationToolFailed(:final failure, output: final value) =>
          32 + text(failure.message) + output(value),
      };
      if (userInput != null) {
        n += 32 + text(userInput.interactionId);
        for (final q in userInput.questions) {
          n += 40 + text(q.id);
        }
        switch (userInput.state) {
          case ConversationUserInputPending() ||
              ConversationUserInputCancelled():
            break;
          case ConversationUserInputResolved(:final answers):
            for (final a in answers) {
              n += 32 + text(a.questionId);
            }
        }
      }
      if (wait != null) {
        n += 32;
        switch (wait.intent) {
          case ThreadWaitTimerIntentView():
            n += 16;
          case ThreadWaitEventsIntentView(:final targets):
            for (final t in targets) {
              n += 32 + text(t.taskId) + text(t.toolName) + text(t.summary);
            }
        }
      }
    case ConversationAgentDescriptor(:final value):
      final i = value.identity;
      n +=
          32 +
          text(i.id) +
          text(i.path) +
          text(i.parentPath) +
          text(i.role) +
          text(i.task);
      n += switch (value.lifecycle) {
        QueuedThreadAgentView() || RunningThreadAgentView() => 16,
        SucceededThreadAgentView(:final summary) => 24 + text(summary),
        DeniedThreadAgentView(:final reason) ||
        CancelledThreadAgentView(:final reason) => 24 + text(reason),
        FailedThreadAgentView(:final error) => 24 + text(error),
      };
    case ConversationTurnDescriptor(:final value):
      n += text(value.inputId) + _demoTurnStateBytes(value.state);
    case ConversationInferenceDescriptor(:final value):
      n +=
          64 +
          text(value.inferenceId) +
          text(value.model) +
          switch (value.lifecycle) {
            RunningThreadInferenceView() ||
            CompletedThreadInferenceView() => 16,
            FailedThreadInferenceView(:final error) => 24 + text(error),
            CancelledThreadInferenceView(:final reason) => 24 + text(reason),
          };
    case ConversationSkillDescriptor(:final value):
      n +=
          text(value.name) +
          text(value.source) +
          text(value.providerId) +
          text(value.resourceBase.value) +
          text(value.cause.id);
    case ConversationFileDescriptor(:final value):
      n += text(value.path) + text(value.mediaType);
    case ConversationContextCompactionDescriptor():
      n += 32;
  }
  return n;
}

int _demoAttachmentBytes(List<ThreadAttachmentView> values) => values.fold(
  16,
  (n, v) =>
      n +
      48 +
      utf8.encode(v.id).length +
      utf8.encode(v.mediaType).length +
      utf8.encode(v.filename ?? '').length,
);
int _demoTurnStateBytes(StudioTurnState state) {
  int stringBytes(String? value) =>
      value == null ? 0 : 8 + utf8.encode(value).length;
  var total = 64 + stringBytes(state.reason);
  total += switch (state) {
    FailedStudioTurnState(:final failure) =>
      stringBytes(failure.category) +
          stringBytes(failure.providerKind) +
          stringBytes(failure.code),
    BudgetLimitedStudioTurnState(:final rollover) => switch (rollover) {
      RolloverFailed(:final error) => stringBytes(error),
      RolloverNotAttempted() || RolloverSucceeded() => 0,
    },
    QueuedStudioTurnState() ||
    RunningStudioTurnState() ||
    CompletedStudioTurnState() ||
    CancelledStudioTurnState() => 0,
  };
  return total;
}

/// The authoritative plan decision is a small field value, not free-form body preview.
bool _demoPlanMarker(ConversationItem item, ConversationFieldPreview field) {
  if (field.field case ThreadToolUserInputFieldView(
    :final questionIndex,
    part: ThreadUserInputAnswerFieldPartView(:final answerIndex),
  )) {
    final input = item.userInput;
    if (input == null ||
        questionIndex < 0 ||
        questionIndex >= input.questions.length) {
      return false;
    }
    final question = input.questions[questionIndex];
    if (question.id != agentSessionPlanConfirmationQuestionId ||
        question.isSecret) {
      return false;
    }
    if (input.state case ConversationUserInputResolved(:final answers)) {
      if (!answers.any(
        (answer) =>
            answer.questionId == question.id &&
            !answer.redacted &&
            answerIndex >= 0 &&
            answerIndex < answer.answerCount,
      )) {
        return false;
      }
      return field.text == agentSessionPlanApproveAnswer ||
          field.text == agentSessionPlanReviseAnswer;
    }
  }
  return false;
}
