// 宿主侧只读观测层：严格解析当前 `timeline`/`timelineScroll` 诊断，并在请求时扫描
// 真实 widget/render tree 取得挂载行几何。
//
// 这里没有任何生产状态：脚本只读快照，几何只在调用时读取，不维护每行测量表、不写
// pixels、不按帧采样。缺失字段是观测失败（抛错），绝不用 0/固定值伪装通过
// （design/26 §26.9）。
import 'dart:convert';

/// 一个展示代次的只读事实。
final class TimelineObservation {
  TimelineObservation._({
    required this.threadId,
    required this.generation,
    required this.ready,
    required this.mode,
    required this.connection,
    required this.appliedVersion,
    required this.itemCount,
    required this.itemIds,
    required this.olderCursor,
    required this.hasOlder,
    required this.loadingOlder,
    required this.olderError,
    required this.hasNewOutput,
    required this.preparingLive,
    required this.items,
  });

  /// 当前快照里的展示事实；`timeline` 为 null（没有展示）时返回 null。
  ///
  /// 存在但不是当前契约的 Map（缺字段/类型不符）时抛错：那是观测失败，不是“没有”。
  static TimelineObservation? optional(Map<String, dynamic> snapshot) {
    final raw = snapshot['timeline'];
    if (raw == null) return null;
    if (raw is! Map) {
      throw StateError('timeline fact is not an object: $raw');
    }
    final map = raw.cast<String, dynamic>();
    final items = <TimelineItemObservation>[];
    final rawItems = map['items'];
    if (rawItems is! List) {
      throw StateError('timeline.items is missing: $map');
    }
    for (final item in rawItems) {
      if (item is! Map) {
        throw StateError('timeline item is not an object: $item');
      }
      items.add(TimelineItemObservation._parse(item.cast<String, dynamic>()));
    }
    final itemIds = <String>[];
    final rawIds = map['itemIds'];
    if (rawIds is! List) {
      throw StateError('timeline.itemIds is missing: $map');
    }
    for (final id in rawIds) {
      if (id is! String) {
        throw StateError('timeline.itemIds is not a string list');
      }
      itemIds.add(id);
    }
    return TimelineObservation._(
      threadId: _string(map, 'threadId', 'timeline'),
      generation: _int(map, 'generation', 'timeline'),
      ready: _bool(map, 'ready', 'timeline'),
      mode: _string(map, 'mode', 'timeline'),
      connection: _string(map, 'connection', 'timeline'),
      appliedVersion: _intOrNull(map, 'appliedVersion', 'timeline'),
      itemCount: _int(map, 'itemCount', 'timeline'),
      itemIds: List.unmodifiable(itemIds),
      olderCursor: _stringOrNull(map, 'olderCursor', 'timeline'),
      hasOlder: _bool(map, 'hasOlder', 'timeline'),
      loadingOlder: _bool(map, 'loadingOlder', 'timeline'),
      olderError: _stringOrNull(map, 'olderError', 'timeline'),
      hasNewOutput: _bool(map, 'hasNewOutput', 'timeline'),
      preparingLive: _bool(map, 'preparingLive', 'timeline'),
      items: List.unmodifiable(items),
    );
  }

  /// 必须存在当前展示事实；没有展示时抛错。
  static TimelineObservation parse(Map<String, dynamic> snapshot) {
    final timeline = optional(snapshot);
    if (timeline == null) {
      throw StateError('timeline display facts are absent');
    }
    return timeline;
  }

  final String threadId;
  final int generation;
  final bool ready;

  /// `live` 或 `history`；这是内容发布策略，不是滚动 owner。
  final String mode;
  final String connection;
  final int? appliedVersion;
  final int itemCount;
  final List<String> itemIds;
  final String? olderCursor;
  final bool hasOlder;
  final bool loadingOlder;
  final String? olderError;
  final bool hasNewOutput;
  final bool preparingLive;
  final List<TimelineItemObservation> items;

  bool get isLive => mode == 'live';

  bool get isHistory => mode == 'history';

  TimelineItemObservation? item(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  Iterable<TimelineItemObservation> ofKind(String kind) =>
      items.where((item) => item.kind == kind);

  /// 当前已加载 canonical 消息的稳定身份；同时核对 `itemIds` 与 `items` 一致。
  void requireConsistentIds() {
    if (itemCount != itemIds.length || itemCount != items.length) {
      throw StateError(
        'timeline item count disagrees: itemCount=$itemCount '
        'itemIds=${itemIds.length} items=${items.length}',
      );
    }
    for (var index = 0; index < items.length; index++) {
      if (items[index].id != itemIds[index]) {
        throw StateError(
          'timeline items/itemIds disagree at $index: '
          '${items[index].id} != ${itemIds[index]}',
        );
      }
    }
  }

  /// canonical 顺序（ordinal 升序）；用于证明分页前插没有错序。
  bool get ordinalAscending {
    for (var index = 1; index < items.length; index++) {
      if (items[index].ordinal <= items[index - 1].ordinal) return false;
    }
    return true;
  }

  Map<String, Object?> summary() => <String, Object?>{
    'threadId': threadId,
    'generation': generation,
    'ready': ready,
    'mode': mode,
    'connection': connection,
    'appliedVersion': appliedVersion,
    'itemCount': itemCount,
    'firstId': itemIds.isEmpty ? null : itemIds.first,
    'lastId': itemIds.isEmpty ? null : itemIds.last,
    'olderCursor': olderCursor,
    'hasOlder': hasOlder,
    'loadingOlder': loadingOlder,
    'olderError': olderError,
    'hasNewOutput': hasNewOutput,
    'preparingLive': preparingLive,
  };
}

/// 一条 canonical item 的轻量 typed 预览（有界，不是全文）。
final class TimelineItemObservation {
  TimelineItemObservation._({
    required this.id,
    required this.ordinal,
    required this.revision,
    required this.saved,
    required this.terminal,
    required this.omittedBytes,
    required this.kind,
    required this.status,
    required this.text,
    required this.channel,
    required this.details,
    required this.attachments,
    required this.tool,
    required this.userInput,
  });

  static TimelineItemObservation _parse(Map<String, dynamic> map) {
    final details = <TimelineDetailObservation>[];
    final rawDetails = map['details'];
    if (rawDetails is! List) {
      throw StateError('timeline item details missing: ${map['id']}');
    }
    for (final detail in rawDetails) {
      if (detail is! Map) {
        throw StateError('timeline detail is not an object: $detail');
      }
      details.add(
        TimelineDetailObservation._parse(detail.cast<String, dynamic>()),
      );
    }
    final attachments = <TimelineAttachmentObservation>[];
    final rawAttachments = map['attachments'];
    if (rawAttachments is! List) {
      throw StateError('timeline item attachments missing: ${map['id']}');
    }
    for (final attachment in rawAttachments) {
      if (attachment is! Map) {
        throw StateError('timeline attachment is not an object: $attachment');
      }
      attachments.add(
        TimelineAttachmentObservation._parse(
          attachment.cast<String, dynamic>(),
        ),
      );
    }
    final tool = map['tool'];
    final userInput = map['userInput'];
    final kind = _string(map, 'kind', 'timeline item');
    final channel = _requiredStringOrNull(map, 'channel', 'timeline item');
    // 频道必须与 canonical kind 对应：文本条目的权威频道不能缺失或被猜成
    // finalAnswer，非文本条目不允许带频道；未知 kind 直接拒绝而不是放行。
    _requireChannelForKind(kind, channel);
    return TimelineItemObservation._(
      id: _string(map, 'id', 'timeline item'),
      ordinal: _int(map, 'ordinal', 'timeline item'),
      revision: _int(map, 'revision', 'timeline item'),
      saved: _bool(map, 'saved', 'timeline item'),
      terminal: _bool(map, 'terminal', 'timeline item'),
      omittedBytes: _int(map, 'omittedBytes', 'timeline item'),
      kind: kind,
      status: _string(map, 'status', 'timeline item'),
      text: _string(map, 'text', 'timeline item'),
      channel: channel,
      details: List.unmodifiable(details),
      attachments: List.unmodifiable(attachments),
      tool: tool is Map
          ? TimelineToolObservation._parse(tool.cast<String, dynamic>())
          : null,
      userInput: userInput is Map
          ? TimelineUserInputObservation._parse(
              userInput.cast<String, dynamic>(),
            )
          : null,
    );
  }

  final String id;
  final int ordinal;
  final int revision;
  final bool saved;
  final bool terminal;
  final int omittedBytes;
  final String kind;
  final String status;

  /// 已脱敏的有界正文预览；完整字段走详情查看器。
  final String text;

  /// 文本条目的权威频道（`user`/`parentAgent`/`commentary`/`finalAnswer`）；
  /// 非文本条目为 null。`agentMessage` 同时覆盖 commentary 与 finalAnswer，
  /// 因此不能用 kind 推断回答。
  final String? channel;
  final List<TimelineDetailObservation> details;
  final List<TimelineAttachmentObservation> attachments;
  final TimelineToolObservation? tool;
  final TimelineUserInputObservation? userInput;

  int get textBytes => utf8.encode(text).length;

  bool get isCommentary => kind == 'agentMessage' && channel == 'commentary';

  /// 真正的最终回答：`agentMessage` 且权威频道是 finalAnswer。
  bool get isFinalAnswer => kind == 'agentMessage' && channel == 'finalAnswer';

  TimelineDetailObservation? detail(String field) {
    for (final detail in details) {
      if (detail.field == field) return detail;
    }
    return null;
  }

  /// 正文预览是否被截断（存在 text 详情引用且预览短于真实总字节）。
  bool get textTruncated {
    final ref = detail('text');
    return ref != null && ref.previewBytes < ref.totalBytes;
  }

  int? get textTotalBytes => detail('text')?.totalBytes;
}

final class TimelineDetailObservation {
  const TimelineDetailObservation._({
    required this.field,
    required this.revision,
    required this.totalBytes,
    required this.previewBytes,
  });

  static TimelineDetailObservation _parse(Map<String, dynamic> map) =>
      TimelineDetailObservation._(
        field: _string(map, 'field', 'timeline detail'),
        revision: _int(map, 'revision', 'timeline detail'),
        totalBytes: _int(map, 'totalBytes', 'timeline detail'),
        previewBytes: _int(map, 'previewBytes', 'timeline detail'),
      );

  final String field;
  final int revision;
  final int totalBytes;
  final int previewBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'field': field,
    'revision': revision,
    'totalBytes': totalBytes,
    'previewBytes': previewBytes,
  };
}

final class TimelineAttachmentObservation {
  const TimelineAttachmentObservation._({
    required this.id,
    required this.modality,
    required this.filename,
    required this.byteSize,
    required this.source,
  });

  static TimelineAttachmentObservation _parse(Map<String, dynamic> map) =>
      TimelineAttachmentObservation._(
        id: _string(map, 'id', 'timeline attachment'),
        modality: _string(map, 'modality', 'timeline attachment'),
        filename: _string(map, 'filename', 'timeline attachment'),
        byteSize: _int(map, 'byteSize', 'timeline attachment'),
        source: _stringOrNull(map, 'source', 'timeline attachment'),
      );

  final String id;
  final String modality;
  final String filename;
  final int byteSize;

  /// `tool` 表示该附件来自工具调用；null 表示 item 自身。
  final String? source;
}

final class TimelineToolObservation {
  const TimelineToolObservation._({
    required this.name,
    required this.status,
    required this.callId,
    required this.arguments,
    required this.result,
    required this.progressBytes,
    required this.itemRevision,
    required this.denialReason,
    required this.workingDirectory,
    required this.exitCode,
    required this.attachments,
  });

  static TimelineToolObservation _parse(Map<String, dynamic> map) {
    final attachments = <TimelineAttachmentObservation>[];
    final raw = map['attachments'];
    if (raw is! List) throw StateError('tool attachments missing: $map');
    for (final attachment in raw) {
      if (attachment is! Map) {
        throw StateError('tool attachment is not an object: $attachment');
      }
      attachments.add(
        TimelineAttachmentObservation._parse(
          attachment.cast<String, dynamic>(),
        ),
      );
    }
    return TimelineToolObservation._(
      name: _string(map, 'name', 'timeline tool'),
      status: _string(map, 'status', 'timeline tool'),
      callId: _string(map, 'callId', 'timeline tool'),
      arguments: _string(map, 'arguments', 'timeline tool'),
      result: _stringOrNull(map, 'result', 'timeline tool'),
      progressBytes: _int(map, 'progressBytes', 'timeline tool'),
      itemRevision: _int(map, 'itemRevision', 'timeline tool'),
      denialReason: _stringOrNull(map, 'denialReason', 'timeline tool'),
      workingDirectory: _stringOrNull(map, 'workingDirectory', 'timeline tool'),
      exitCode: _intOrNull(map, 'exitCode', 'timeline tool'),
      attachments: List.unmodifiable(attachments),
    );
  }

  final String name;
  final String status;
  final String callId;
  final String arguments;
  final String? result;

  /// 预览结果字节数：逐次增长即在途真实产出。
  final int progressBytes;
  final int itemRevision;
  final String? denialReason;
  final String? workingDirectory;
  final int? exitCode;
  final List<TimelineAttachmentObservation> attachments;
}

final class TimelineUserInputObservation {
  const TimelineUserInputObservation._({
    required this.interactionId,
    required this.state,
    required this.isPlanConfirmation,
    required this.planDecision,
  });

  static TimelineUserInputObservation _parse(Map<String, dynamic> map) =>
      TimelineUserInputObservation._(
        interactionId: _string(map, 'interactionId', 'timeline user input'),
        state: _string(map, 'state', 'timeline user input'),
        isPlanConfirmation: _requiredBool(
          map,
          'isPlanConfirmation',
          'timeline user input',
        ),
        planDecision: _stringOrNull(map, 'planDecision', 'timeline user input'),
      );

  final String interactionId;

  /// `pending`、`resolved` 或 `cancelled`。
  final String state;
  final bool isPlanConfirmation;
  final String? planDecision;
}

/// 当前代次标准 `ScrollController` 的真实几何。
final class TimelineScrollObservation {
  const TimelineScrollObservation._({
    required this.threadId,
    required this.generation,
    required this.pixels,
    required this.minScrollExtent,
    required this.maxScrollExtent,
    required this.viewportDimension,
    required this.extentBefore,
    required this.extentAfter,
    required this.atLiveEdge,
    required this.isScrolling,
  });

  /// `timelineScroll` 为 null 表示视图尚未发布几何；类型不符则抛错。
  static TimelineScrollObservation? optional(Map<String, dynamic> snapshot) {
    final raw = snapshot['timelineScroll'];
    if (raw == null) return null;
    if (raw is! Map) {
      throw StateError('timelineScroll fact is not an object: $raw');
    }
    final map = raw.cast<String, dynamic>();
    return TimelineScrollObservation._(
      threadId: _stringOrNull(map, 'threadId', 'timelineScroll'),
      generation: _int(map, 'generation', 'timelineScroll'),
      pixels: _doubleOrNull(map, 'pixels', 'timelineScroll'),
      minScrollExtent: _doubleOrNull(map, 'minScrollExtent', 'timelineScroll'),
      maxScrollExtent: _doubleOrNull(map, 'maxScrollExtent', 'timelineScroll'),
      viewportDimension: _doubleOrNull(
        map,
        'viewportDimension',
        'timelineScroll',
      ),
      extentBefore: _doubleOrNull(map, 'extentBefore', 'timelineScroll'),
      extentAfter: _doubleOrNull(map, 'extentAfter', 'timelineScroll'),
      atLiveEdge: _bool(map, 'atLiveEdge', 'timelineScroll'),
      isScrolling: _bool(map, 'isScrolling', 'timelineScroll'),
    );
  }

  /// 必须已发布几何；尚未发布时抛错。
  static TimelineScrollObservation parse(Map<String, dynamic> snapshot) {
    final scroll = optional(snapshot);
    if (scroll == null) {
      throw StateError('timelineScroll geometry is absent');
    }
    return scroll;
  }

  final String? threadId;
  final int generation;
  final double? pixels;
  final double? minScrollExtent;
  final double? maxScrollExtent;
  final double? viewportDimension;
  final double? extentBefore;
  final double? extentAfter;

  /// 反向列表 offset 0 的几何事实，**不等于** Live 模式。
  final bool atLiveEdge;
  final bool isScrolling;

  bool get laidOut =>
      pixels != null && maxScrollExtent != null && viewportDimension != null;

  double get extentAfterOrZero => extentAfter ?? 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'threadId': threadId,
    'generation': generation,
    'pixels': pixels,
    'minScrollExtent': minScrollExtent,
    'maxScrollExtent': maxScrollExtent,
    'viewportDimension': viewportDimension,
    'extentBefore': extentBefore,
    'extentAfter': extentAfter,
    'atLiveEdge': atLiveEdge,
    'isScrolling': isScrolling,
  };
}

/// 一个矩形（视口坐标系，或全局坐标系，见 [TimelineRowsObservation.frame]）。
final class TimelineRect {
  const TimelineRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  static TimelineRect? _parse(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final left = map['left'];
    final top = map['top'];
    final width = map['width'];
    final height = map['height'];
    if (left is! num || top is! num || width is! num || height is! num) {
      return null;
    }
    return TimelineRect(
      left: left.toDouble(),
      top: top.toDouble(),
      width: width.toDouble(),
      height: height.toDouble(),
    );
  }

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;

  double get bottom => top + height;

  double get centerY => top + height / 2;

  Map<String, Object?> toJson() => <String, Object?>{
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };
}

/// 请求时扫描到的一行挂载状态。
final class TimelineRowObservation {
  const TimelineRowObservation({
    required this.id,
    required this.mounted,
    required this.painted,
    required this.intersects,
    required this.rect,
    required this.reason,
  });

  static TimelineRowObservation _parse(Map<String, dynamic> map) {
    final mounted = map['mounted'];
    return TimelineRowObservation(
      id: _string(map, 'id', 'timeline row'),
      mounted: mounted is bool ? mounted : true,
      painted: map['painted'] == true,
      intersects: map['intersects'] == true,
      rect: TimelineRect._parse(map['rect']),
      reason: _stringOrNull(map, 'reason', 'timeline row'),
    );
  }

  final String id;

  /// false 表示当前没有对应 Element（合理离屏或尚未布局）。
  final bool mounted;
  final bool painted;
  final bool intersects;
  final TimelineRect? rect;
  final String? reason;

  /// 可比较的可见位置：只有可测且相交的行才有值。
  double? get visibleTop => intersects ? rect?.top : null;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'mounted': mounted,
    'painted': painted,
    'intersects': intersects,
    if (rect != null) 'rect': rect!.toJson(),
    if (reason != null) 'reason': reason,
  };
}

/// 一次只读几何观察的结果。
final class TimelineRowsObservation {
  const TimelineRowsObservation({
    required this.frame,
    required this.viewport,
    required this.viewportGlobal,
    required this.rows,
    required this.missing,
    required this.requested,
  });

  static TimelineRowsObservation parse(Map<String, dynamic> json) {
    if (json['ok'] != true) {
      throw StateError('timeline geometry failed: $json');
    }
    final viewport = TimelineRect._parse(json['viewport']);
    if (viewport == null) {
      throw StateError('timeline geometry has no viewport: $json');
    }
    final rawRows = json['rows'];
    final rows = <TimelineRowObservation>[];
    if (rawRows is List) {
      for (final row in rawRows) {
        if (row is! Map) {
          throw StateError('timeline geometry row is not an object: $row');
        }
        rows.add(TimelineRowObservation._parse(row.cast<String, dynamic>()));
      }
    }
    final missing = <String>[];
    final rawMissing = json['missing'];
    if (rawMissing is List) {
      for (final id in rawMissing) {
        if (id is String) missing.add(id);
      }
    }
    final requested = json['requested'];
    return TimelineRowsObservation(
      frame: json['frame'] is String ? json['frame'] as String : 'viewport',
      viewport: viewport,
      viewportGlobal: TimelineRect._parse(json['viewportGlobal']),
      rows: List.unmodifiable(rows),
      missing: List.unmodifiable(missing),
      requested: requested is num ? requested.toInt() : null,
    );
  }

  /// `viewport` 表示 viewport 与 rows.rect 都以视口左上角为原点。
  final String frame;
  final TimelineRect viewport;
  final TimelineRect? viewportGlobal;
  final List<TimelineRowObservation> rows;

  /// 没有对应 Element 的 id；Element 存在但不可测会在 rows 里给出 reason。
  final List<String> missing;
  final int? requested;

  /// 与视口真实相交且可测的行，按可见位置自上而下。
  List<TimelineRowObservation> get visible {
    final visible = <TimelineRowObservation>[
      for (final row in rows)
        if (row.intersects && row.rect != null) row,
    ];
    visible.sort((a, b) => a.rect!.top.compareTo(b.rect!.top));
    return visible;
  }

  TimelineRowObservation? row(String id) {
    for (final row in rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'frame': frame,
    'viewport': viewport.toJson(),
    if (viewportGlobal != null) 'viewportGlobal': viewportGlobal!.toJson(),
    'rows': [for (final row in rows) row.toJson()],
    'missing': missing,
    'requested': requested,
  };
}

/// 一次 Driver 请求的最小接口（`FlutterDriverSession.requestData` 与
/// `FlutterDriver.requestData` 都满足它）。
typedef DriverRequest = Future<String> Function(
  String message, {
  Duration? timeout,
});

/// 请求时的行/视口几何探针（Driver-only，只读）。
///
/// 生产端没有每行 GlobalKey 表；这里按 canonical row key 现场遍历挂载子树，不写
/// pixels、不缓存全表、不参与任何滚动决策。
final class TimelineRowsProbe {
  const TimelineRowsProbe(this._request);

  final DriverRequest _request;

  Future<TimelineRowsObservation> read({List<String>? rowIds}) async {
    final raw = await _request(
      jsonEncode(<String, Object?>{
        'cmd': 'timeline-geometry',
        'rowIds': rowIds,
      }),
      timeout: const Duration(seconds: 20),
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('timeline geometry response is not an object: $raw');
    }
    return TimelineRowsObservation.parse(decoded);
  }

  /// 当前真正可见（相交且可测）的挂载行。
  Future<List<TimelineRowObservation>> visible() async =>
      (await read()).visible;
}

/// 一条真实指针输入前/后，同一可见行的位移。
final class VisibleRowDisplacement {
  const VisibleRowDisplacement({
    required this.rowId,
    required this.beforeTop,
    required this.afterTop,
    required this.viewportHeight,
  });

  final String rowId;
  final double? beforeTop;
  final double? afterTop;
  final double viewportHeight;

  /// 行内容向上移动的像素数；目标不可见时为 null（不当成 0）。
  double? get contentMoved =>
      beforeTop == null || afterTop == null ? null : beforeTop! - afterTop!;

  Map<String, Object?> toJson() => <String, Object?>{
    'rowId': rowId,
    'beforeTop': beforeTop,
    'afterTop': afterTop,
    'viewportHeight': viewportHeight,
    'contentMoved': contentMoved,
  };
}

/// canonical kind 与文本频道必须一一对应。
///
/// `agentMessage` 同时覆盖 commentary 与 finalAnswer，所以不能只看 kind；反过来，
/// 推理/工具/Turn 等非文本条目不允许携带频道。未知 kind 视为契约不符而拒绝。
void _requireChannelForKind(String kind, String? channel) {
  switch (kind) {
    case 'userMessage':
      _requireChannel(kind, channel, const {'user'});
    case 'parentAgentMessage':
      _requireChannel(kind, channel, const {'parentAgent'});
    case 'agentMessage':
      _requireChannel(kind, channel, const {'commentary', 'finalAnswer'});
    case 'raw':
    case 'reasoning':
    case 'toolCall':
    case 'agent':
    case 'turn':
    case 'inference':
    case 'skill':
    case 'file':
    case 'contextCompaction':
      if (channel != null) {
        throw StateError(
          'timeline item kind $kind must not carry channel $channel',
        );
      }
    default:
      throw StateError('timeline item kind is not a canonical kind: $kind');
  }
}

void _requireChannel(String kind, String? channel, Set<String> allowed) {
  if (channel == null || !allowed.contains(channel)) {
    throw StateError(
      'timeline item kind $kind requires channel in $allowed, got $channel',
    );
  }
}

/// 键必须存在；值为 null 是合法事实，缺失是观测失败。
String? _requiredStringOrNull(
  Map<String, dynamic> map,
  String key,
  String owner,
) {
  if (!map.containsKey(key)) {
    throw StateError('$owner.$key is missing');
  }
  return _stringOrNull(map, key, owner);
}

/// 键必须存在且为 bool；缺失不默认为 false。
bool _requiredBool(Map<String, dynamic> map, String key, String owner) {
  if (!map.containsKey(key)) {
    throw StateError('$owner.$key is missing');
  }
  return _bool(map, key, owner);
}

String _string(Map<String, dynamic> map, String key, String owner) {
  final value = map[key];
  if (value is! String) {
    throw StateError('$owner.$key is not a string: $value');
  }
  return value;
}

String? _stringOrNull(Map<String, dynamic> map, String key, String owner) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) {
    throw StateError('$owner.$key is not a string: $value');
  }
  return value;
}

int _int(Map<String, dynamic> map, String key, String owner) {
  final value = map[key];
  if (value is! num) throw StateError('$owner.$key is not a number: $value');
  return value.toInt();
}

int? _intOrNull(Map<String, dynamic> map, String key, String owner) {
  final value = map[key];
  if (value == null) return null;
  if (value is! num) throw StateError('$owner.$key is not a number: $value');
  return value.toInt();
}

bool _bool(Map<String, dynamic> map, String key, String owner) {
  final value = map[key];
  if (value is! bool) throw StateError('$owner.$key is not a bool: $value');
  return value;
}

double? _doubleOrNull(Map<String, dynamic> map, String key, String owner) {
  final value = map[key];
  if (value == null) return null;
  if (value is! num) throw StateError('$owner.$key is not a number: $value');
  return value.toDouble();
}
