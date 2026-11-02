// 宿主侧只读观测层：严格解析当前 `timeline`/`timelineScroll` 诊断，并在请求时扫描
// 真实 widget/render tree 取得挂载行几何。
//
// 这里没有任何生产状态：脚本只读快照，几何只在调用时读取，不维护每行测量表、不写
// pixels、不按帧采样。缺失字段是观测失败（抛错），绝不用 0/固定值伪装通过
// （design/26 §26.9）。
import 'dart:convert';

import 'timeline_group_observation.dart';

/// Canonical read-only observation of the currently published activity parts.
///
/// This is decoded directly from `conversationActivity`; it does not cache or
/// synthesize product state. The JSON value preserves activity/source identity,
/// original part identity, order, text and the producer's UTF-8 byte declaration.
String? conversationActivityContentObservation(Map<String, dynamic> snapshot) {
  final rawActivity = snapshot['conversationActivity'];
  if (rawActivity == null) return null;
  if (rawActivity is! Map) {
    throw StateError('conversationActivity is not an object: $rawActivity');
  }
  final activity = rawActivity.cast<String, dynamic>();
  final identity = activity['identity'];
  if (identity is! String) {
    throw StateError('conversationActivity.identity is missing');
  }

  List<Map<String, Object?>> textParts(String field) {
    final rawParts = activity[field];
    if (rawParts is! List) {
      throw StateError('conversationActivity.$field is missing');
    }
    final result = <Map<String, Object?>>[];
    final seenIds = <String>{};
    for (var index = 0; index < rawParts.length; index++) {
      final rawPart = rawParts[index];
      if (rawPart is! Map || rawPart['complete'] is! bool) {
        throw StateError(
          'conversationActivity.$field[$index] lacks bool complete state',
        );
      }
      final itemId = rawPart['itemId'];
      if (itemId is! String || !seenIds.add(itemId)) {
        throw StateError(
          'conversationActivity.$field has invalid/duplicate itemId: $itemId',
        );
      }
      final parsed = parseConversationActivityPart(
        rawParts[index],
        index: index,
        identityField: 'itemId',
        context: 'conversationActivity.$field',
      );
      parsed['complete'] = rawPart['complete'];
      result.add(parsed);
    }
    return result;
  }

  final rawTools = activity['toolDetails'];
  if (rawTools is! List) {
    throw StateError('conversationActivity.toolDetails is missing');
  }
  final tools = <Map<String, Object?>>[];
  for (var toolIndex = 0; toolIndex < rawTools.length; toolIndex++) {
    final rawTool = rawTools[toolIndex];
    if (rawTool is! Map) {
      throw StateError('conversationActivity tool is not an object');
    }
    final tool = rawTool.cast<String, dynamic>();
    final callId = tool['callId'];
    final state = tool['state'];
    final rawParts = tool['outputParts'];
    if (callId is! String || state is! String || rawParts is! List) {
      throw StateError(
        'conversationActivity tool lacks call/state/outputParts',
      );
    }
    final seenPartIds = <String>{};
    for (final rawPart in rawParts) {
      if (rawPart is! Map ||
          rawPart['partId'] is! String ||
          !seenPartIds.add(rawPart['partId'] as String)) {
        throw StateError(
          'conversationActivity tool $callId has invalid/duplicate partId',
        );
      }
    }
    tools.add(<String, Object?>{
      'callId': callId,
      'state': state,
      'outputParts': [
        for (var index = 0; index < rawParts.length; index++)
          parseConversationActivityPart(
            rawParts[index],
            index: index,
            identityField: 'partId',
            context: 'conversationActivity tool $callId outputParts',
          ),
      ],
    });
  }
  return jsonEncode(<String, Object?>{
    'identity': identity,
    'turnId': activity['turnId'],
    'executionId': activity['executionId'],
    'reasoningParts': textParts('reasoningParts'),
    'responseParts': textParts('responseParts'),
    'tools': tools,
  });
}

/// Whether two activity observations show changed text on an unchanged activity
/// identity. Counters, status, byte declarations, and identity changes alone do
/// not count as content progress.
bool conversationActivityContentChanged(String? before, String? after) {
  if (before == null || after == null) return false;
  final left = jsonDecode(before);
  final right = jsonDecode(after);
  if (left is! Map ||
      right is! Map ||
      left['identity'] != right['identity'] ||
      left['turnId'] != right['turnId'] ||
      left['executionId'] != right['executionId']) {
    return false;
  }
  for (final field in const ['reasoningParts', 'responseParts']) {
    if (activityPartTextChanged(
      left[field],
      right[field],
      identityField: 'itemId',
    )) {
      return true;
    }
  }
  final oldTools = left['tools'];
  final newTools = right['tools'];
  if (oldTools is! List || newTools is! List) return false;
  final oldByCall = <String, Map>{};
  for (final tool in oldTools) {
    if (tool is Map && tool['callId'] is String) {
      oldByCall[tool['callId'] as String] = tool;
    }
  }
  for (final tool in newTools) {
    if (tool is! Map || tool['callId'] is! String) continue;
    final oldTool = oldByCall[tool['callId'] as String];
    if (activityPartTextChanged(
      oldTool?['outputParts'],
      tool['outputParts'],
      identityField: 'partId',
    )) {
      return true;
    }
  }
  return false;
}

bool activityPartTextChanged(
  Object? before,
  Object? after, {
  required String identityField,
}) {
  if (before is! List || after is! List) return false;
  final oldById = <String, String>{};
  for (final value in before) {
    if (value is Map &&
        value[identityField] is String &&
        value['text'] is String) {
      oldById[value[identityField] as String] = value['text'] as String;
    }
  }
  for (final value in after) {
    if (value is! Map ||
        value[identityField] is! String ||
        value['text'] is! String) {
      continue;
    }
    final id = value[identityField] as String;
    final text = value['text'] as String;
    final previousText = oldById[id];
    if (previousText != null && previousText != text) {
      return true;
    }
  }
  return false;
}

Map<String, Object?> parseConversationActivityPart(
  Object? raw, {
  required int index,
  required String identityField,
  required String context,
}) {
  if (raw is! Map) throw StateError('$context[$index] is not an object');
  final part = raw.cast<String, dynamic>();
  final identity = part[identityField];
  final text = part['text'];
  final byteLength = part['byteLength'];
  if (identity is! String || text is! String || byteLength is! int) {
    throw StateError('$context[$index] lacks $identityField/text/byteLength');
  }
  if (part.containsKey('complete') && part['complete'] is! bool) {
    throw StateError('$context[$index] complete state must be bool');
  }
  if (utf8.encode(text).length != byteLength) {
    throw StateError('$context[$index] byteLength disagrees with text');
  }
  return <String, Object?>{
    'index': index,
    identityField: identity,
    'text': text,
    'byteLength': byteLength,
    if (part.containsKey('complete')) 'complete': part['complete'],
  };
}

/// Current display, layout and viewport demand have all settled. EOF can be short.
bool timelineViewportSettled(Map<String, dynamic> snapshot) {
  final timeline = TimelineObservation.optional(snapshot);
  final scroll = TimelineScrollObservation.optional(snapshot);
  return timeline != null &&
      timeline.ready &&
      timeline.connection == 'ready' &&
      !timeline.loadingOlder &&
      timeline.olderError == null &&
      scroll != null &&
      scroll.laidOut &&
      !scroll.isScrolling &&
      scroll.generation == timeline.generation &&
      ((scroll.maxScrollExtent ?? 0) > 0.5 || !timeline.hasOlder);
}

/// A second matching observation rules out sampling a page's layout transition.
/// This is Driver-only observation, not a product cache or timing-based success.
final class TimelineViewportStability {
  Object? _previous;

  bool accept(Map<String, dynamic> snapshot) {
    if (!timelineViewportSettled(snapshot)) {
      _previous = null;
      return false;
    }
    final timeline = TimelineObservation.parse(snapshot);
    final scroll = TimelineScrollObservation.parse(snapshot);
    final stamp = (
      timeline.threadId,
      timeline.generation,
      timeline.itemIds.join('\u0000'),
      timeline.itemCount,
      timeline.olderCursor,
      timeline.hasOlder,
      scroll.viewportDimension,
      scroll.maxScrollExtent,
      scroll.pixels,
    );
    final stable = _previous == stamp;
    _previous = stamp;
    return stable;
  }
}

/// 一个展示代次的只读事实。
final class TimelineObservation {
  TimelineObservation._({
    required this.threadId,
    required this.generation,
    required this.ready,
    required this.mode,
    required this.connection,
    required this.loadedCount,
    required this.itemCount,
    required this.itemIds,
    required this.olderCursor,
    required this.hasOlder,
    required this.loadingOlder,
    required this.olderError,
    required this.olderErrorCode,
    required this.olderErrorCorrelationId,
    required this.hasNewOutput,
    required this.items,
    required this.children,
    required this.groups,
    required this.appliedSets,
    required this.appliedPrepends,
    required this.appliedAppends,
    required this.firstContentLayout,
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
      loadedCount: _intOrNull(map, 'loadedCount', 'timeline'),
      itemCount: _int(map, 'itemCount', 'timeline'),
      itemIds: List.unmodifiable(itemIds),
      olderCursor: _stringOrNull(map, 'olderCursor', 'timeline'),
      hasOlder: _bool(map, 'hasOlder', 'timeline'),
      loadingOlder: _bool(map, 'loadingOlder', 'timeline'),
      olderError: _stringOrNull(map, 'olderError', 'timeline'),
      olderErrorCode: _stringOrNull(map, 'olderErrorCode', 'timeline'),
      olderErrorCorrelationId: _stringOrNull(
        map,
        'olderErrorCorrelationId',
        'timeline',
      ),
      hasNewOutput: _bool(map, 'hasNewOutput', 'timeline'),
      items: List.unmodifiable(items),
      children: [
        for (final child in _requiredList(map, 'children', 'timeline'))
          TimelineChildrenObservation.parse(
            (child as Map).cast<String, dynamic>(),
          ),
      ],
      groups: List.unmodifiable([
        for (final group in timelineGroupDisplays(snapshot))
          TimelineGroupObservation.parse(
            group,
            _int(map, 'generation', 'timeline'),
          ),
      ]),
      appliedSets: _intOrNull(map, 'appliedSets', 'timeline'),
      appliedPrepends: _intOrNull(map, 'appliedPrepends', 'timeline'),
      appliedAppends: _intOrNull(map, 'appliedAppends', 'timeline'),
      firstContentLayout: map['firstContentLayout'] == null
          ? null
          : TimelineContentLayoutObservation.parse(
              (map['firstContentLayout'] as Map).cast<String, dynamic>(),
              generation: _int(map, 'generation', 'timeline'),
              itemIds: itemIds,
            ),
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
  final int? loadedCount;
  final int itemCount;
  final List<String> itemIds;
  final String? olderCursor;
  final bool hasOlder;
  final bool loadingOlder;
  final String? olderError;
  final String? olderErrorCode;
  final String? olderErrorCorrelationId;
  final bool hasNewOutput;
  final List<TimelineItemObservation> items;
  final List<TimelineChildrenObservation> children;
  final List<TimelineGroupObservation> groups;
  final int? appliedSets;
  final int? appliedPrepends;
  final int? appliedAppends;
  final TimelineContentLayoutObservation? firstContentLayout;

  /// Search only already expanded displays; this never flattens their ordering into Main.
  Iterable<TimelineItemObservation> get expandedItems sync* {
    yield* items;
    for (final group in groups) {
      if (!group.expanded || group.loading) continue;
      if (group.error != null) {
        throw StateError('Ordinary group read failed: ${group.error}');
      }
      yield* group.items;
    }
    for (final child in children) {
      yield* child.items;
    }
  }

  TimelineGroupObservation groupContainingItem(String id) => groups.singleWhere(
    (group) => group.expanded && group.items.any((item) => item.id == id),
  );

  TimelineChildrenObservation? childrenFor(String parentId) {
    for (final child in children) {
      if (child.parentId == parentId) return child;
    }
    return null;
  }

  TimelineChildrenObservation childrenContaining(String itemId) =>
      children.singleWhere((child) => child.itemIds.contains(itemId));

  TimelineItemObservation? expandedItem(String itemId) {
    for (final item in expandedItems) {
      if (item.id == itemId) return item;
    }
    return null;
  }

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
    if (itemIds.toSet().length != itemIds.length) {
      throw StateError('Controller contains duplicate Message identities');
    }
  }

  /// 原窗口必须作为连续片段保留；前插或追加不能重排／替换旧消息。
  bool retainsWindow(TimelineObservation previous, {required bool prepend}) {
    requireConsistentIds();
    previous.requireConsistentIds();
    if (threadId != previous.threadId ||
        generation != previous.generation ||
        itemIds.length < previous.itemIds.length) {
      return false;
    }
    final offset = prepend ? itemIds.length - previous.itemIds.length : 0;
    for (var index = 0; index < previous.itemIds.length; index++) {
      if (itemIds[offset + index] != previous.itemIds[index]) return false;
    }
    return true;
  }

  /// 分页前插和实时追加可同时发生；旧窗口仍须是完整、连续的原始身份片段。
  bool retainsContiguousWindow(TimelineObservation previous) {
    requireConsistentIds();
    previous.requireConsistentIds();
    if (threadId != previous.threadId || generation != previous.generation) {
      return false;
    }
    if (previous.itemIds.isEmpty) return true;
    final start = itemIds.indexOf(previous.itemIds.first);
    if (start < 0 || start + previous.itemCount > itemCount) return false;
    for (var index = 0; index < previous.itemCount; index++) {
      if (itemIds[start + index] != previous.itemIds[index]) return false;
    }
    return true;
  }

  /// Identity retention alone cannot prove which controller operation completed.
  /// These counters are recorded by the real lease after successful application.
  void requireAcceptedOperation(
    TimelineObservation previous, {
    required bool prepend,
  }) {
    requireConsistentIds();
    previous.requireConsistentIds();
    var next = 0;
    var retained =
        threadId == previous.threadId && generation == previous.generation;
    for (final id in previous.itemIds) {
      while (next < itemIds.length && itemIds[next] != id) {
        next++;
      }
      if (next == itemIds.length) {
        retained = false;
        break;
      }
      next++;
    }
    final beforeCount = prepend
        ? previous.appliedPrepends
        : previous.appliedAppends;
    final afterCount = prepend ? appliedPrepends : appliedAppends;
    // Ordinary completion pages may insert a new unit between loaded rows.
    // Retain each old identity in order; contiguity is not a Main guarantee.
    if (!retained ||
        previous.appliedSets == null ||
        previous.appliedSets! <= 0 ||
        appliedSets != previous.appliedSets ||
        beforeCount == null ||
        beforeCount < 0 ||
        afterCount == null ||
        afterCount <= beforeCount) {
      throw StateError(
        'No qualified ${prepend ? 'Prepend' : 'Append'} acceptance: '
        'before=${previous.summary()} after=${summary()}',
      );
    }
  }

  Map<String, Object?> summary() => <String, Object?>{
    'threadId': threadId,
    'generation': generation,
    'ready': ready,
    'mode': mode,
    'connection': connection,
    'loadedCount': loadedCount,
    'itemCount': itemCount,
    'firstId': itemIds.isEmpty ? null : itemIds.first,
    'lastId': itemIds.isEmpty ? null : itemIds.last,
    'olderCursor': olderCursor,
    'hasOlder': hasOlder,
    'loadingOlder': loadingOlder,
    'olderError': olderError,
    'olderErrorCode': olderErrorCode,
    'olderErrorCorrelationId': olderErrorCorrelationId,
    'hasNewOutput': hasNewOutput,
    'appliedSets': appliedSets,
    'appliedPrepends': appliedPrepends,
    'appliedAppends': appliedAppends,
    'firstContentLayout': firstContentLayout?.toJson(),
  };
}

final class TimelineGroupObservation {
  TimelineGroupObservation.parse(Map<String, dynamic> map, this.generation)
    : unitId = map['unitId'] as String,
      expanded = map['expanded'] as bool,
      loading = map['loading'] as bool,
      completionAnchor = map['completionAnchor'] as int?,
      before = map['before'] as String?,
      error = map['error'],
      items = List.unmodifiable([
        for (final item in map['items'] as List)
          TimelineItemObservation.parse((item as Map).cast<String, dynamic>()),
      ]);
  final String unitId;
  final int generation;
  final bool expanded, loading;
  final int? completionAnchor;
  final String? before;
  final Object? error;
  final List<TimelineItemObservation> items;
  List<String> get itemIds => items.map((item) => item.id).toList();
}

List<dynamic> _requiredList(
  Map<String, dynamic> map,
  String key,
  String owner,
) {
  final value = map[key];
  if (value is! List) throw StateError('$owner.$key is not a list');
  return value;
}

final class TimelineChildrenObservation {
  TimelineChildrenObservation._({
    required this.parentId,
    required this.generation,
    required this.ready,
    required this.loadedCount,
    required this.olderCursor,
    required this.loadingOlder,
    required this.error,
    required this.appliedSets,
    required this.appliedPrepends,
    required this.appliedAppends,
    required this.itemIds,
    required this.items,
  });
  factory TimelineChildrenObservation.parse(Map<String, dynamic> map) {
    final items = [
      for (final value in _requiredList(map, 'items', 'Children'))
        TimelineItemObservation._parse((value as Map).cast<String, dynamic>()),
    ];
    final ids = _requiredList(map, 'itemIds', 'Children').cast<String>();
    final count = _int(map, 'loadedCount', 'Children');
    if (count != items.length ||
        ids.length != count ||
        ids.toSet().length != count ||
        List.generate(
          count,
          (index) => items[index].id != ids[index],
        ).any((bad) => bad)) {
      throw StateError(
        'Children controller identity/order/cardinality disagrees',
      );
    }
    return TimelineChildrenObservation._(
      parentId: _string(map, 'parentId', 'Children'),
      generation: _int(map, 'generation', 'Children'),
      ready: _bool(map, 'ready', 'Children'),
      loadedCount: count,
      olderCursor: _stringOrNull(map, 'olderCursor', 'Children'),
      loadingOlder: _bool(map, 'loadingOlder', 'Children'),
      error: _stringOrNull(map, 'error', 'Children'),
      appliedSets: _int(map, 'appliedSets', 'Children'),
      appliedPrepends: _int(map, 'appliedPrepends', 'Children'),
      appliedAppends: _int(map, 'appliedAppends', 'Children'),
      itemIds: List.unmodifiable(ids),
      items: List.unmodifiable(items),
    );
  }
  final String parentId;
  final int generation;
  final bool ready;
  final int loadedCount;
  final String? olderCursor;
  final bool loadingOlder;
  final String? error;
  final int appliedSets;
  final int appliedPrepends;
  final int appliedAppends;
  final List<String> itemIds;
  final List<TimelineItemObservation> items;
}

final class TimelineContentLayoutObservation {
  TimelineContentLayoutObservation._(
    this.selectionId,
    this.generation,
    this.itemId,
    this.selectionStartedMicros,
    this.layoutCompletedMicros,
    this.elapsedMicros,
  );
  factory TimelineContentLayoutObservation.parse(
    Map<String, dynamic> map, {
    required int generation,
    required List<String> itemIds,
  }) {
    final value = TimelineContentLayoutObservation._(
      _int(map, 'selectionId', 'layout'),
      _int(map, 'generation', 'layout'),
      _string(map, 'itemId', 'layout'),
      _int(map, 'selectionStartedMicros', 'layout'),
      _int(map, 'layoutCompletedMicros', 'layout'),
      _int(map, 'elapsedMicros', 'layout'),
    );
    if (value.generation != generation ||
        !itemIds.contains(value.itemId) ||
        value.selectionStartedMicros < 0 ||
        value.elapsedMicros < 0 ||
        value.elapsedMicros !=
            value.layoutCompletedMicros - value.selectionStartedMicros) {
      throw StateError(
        'firstContentLayout has stale identity or inconsistent same-clock timing',
      );
    }
    return value;
  }
  final int selectionId,
      generation,
      selectionStartedMicros,
      layoutCompletedMicros,
      elapsedMicros;
  final String itemId;
  Map<String, Object?> toJson() => {
    'selectionId': selectionId,
    'generation': generation,
    'itemId': itemId,
    'selectionStartedMicros': selectionStartedMicros,
    'layoutCompletedMicros': layoutCompletedMicros,
    'elapsedMicros': elapsedMicros,
  };
}

/// 一条 canonical item 的轻量 typed 预览（有界，不是全文）。
final class TimelineItemObservation {
  factory TimelineItemObservation.parse(Map<String, dynamic> map) =>
      _parse(map);

  TimelineItemObservation._({
    required this.id,
    required this.sealedAt,
    required this.compatibility,
    required this.payloadByteLength,
    required this.presentationContract,
    required this.diagnostic,
    required this.omittedBytes,
    required this.kind,
    required this.status,
    required this.text,
    required this.channel,
    required this.details,
    required this.attachments,
    required this.tool,
    required this.userInput,
    required this.plan,
    required this.atomic,
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
    final plan = map['plan'];
    final kind = _string(map, 'kind', 'timeline item');
    final channel = _requiredStringOrNull(map, 'channel', 'timeline item');
    // Future/invalid/deferred payloads remain observable local diagnostics.
    // A kind is the current payload type, never a guessed legacy DTO variant.
    return TimelineItemObservation._(
      id: _string(map, 'id', 'timeline item'),
      sealedAt: _intOrNull(map, 'sealedAt', 'timeline item'),
      compatibility: _string(map, 'compatibility', 'timeline item'),
      payloadByteLength: _intOrNull(map, 'payloadByteLength', 'timeline item'),
      presentationContract: _stringOrNull(
        map,
        'presentationContract',
        'timeline item',
      ),
      diagnostic: _stringOrNull(map, 'diagnostic', 'timeline item'),
      omittedBytes: _intOrNull(map, 'omittedBytes', 'timeline item'),
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
      plan: plan is Map
          ? TimelinePlanObservation._parse(plan.cast<String, dynamic>())
          : null,
      atomic: map['atomic'] is Map
          ? Map.unmodifiable((map['atomic'] as Map).cast<String, dynamic>())
          : null,
    );
  }

  final String id;
  final Map<String, dynamic>? atomic;
  String? get foregroundTurnId {
    final source = atomic?['source'];
    return source is Map && source['kind'] == 'foregroundTurn'
        ? source['turnId'] as String?
        : null;
  }

  final int? sealedAt;
  final String compatibility;
  final int? payloadByteLength;
  final String? presentationContract;
  final String? diagnostic;
  final int? omittedBytes;
  final String kind;
  final String status;

  /// 已脱敏的有界正文预览；完整字段走详情查看器。
  final String text;

  /// 当前 payload 的明确频道；不从作者、名称或类型推断。
  final String? channel;
  final List<TimelineDetailObservation> details;
  final List<TimelineAttachmentObservation> attachments;
  final TimelineToolObservation? tool;
  final TimelineUserInputObservation? userInput;
  final TimelinePlanObservation? plan;

  int get textBytes => utf8.encode(text).length;

  bool get isCommentary => kind == 'text' && channel == 'commentary';

  /// 真正的最终回答：当前 text payload 且明确频道是 final。
  bool get isFinalAnswer => kind == 'text' && channel == 'final';

  bool get isUserMessage => kind == 'text' && channel == 'user';

  TimelineDetailObservation? detail(String field) {
    for (final detail in details) {
      if (detail.field == field) return detail;
    }
    return null;
  }

  /// 正文预览是否被截断（存在 text 详情引用且预览短于真实总字节）。
  bool get textTruncated {
    final ref = detail('body');
    return ref != null && ref.previewBytes < ref.totalBytes;
  }

  int? get textTotalBytes => detail('body')?.totalBytes;

  /// The complete immutable Driver-published fields for epoch-stability checks.
  Map<String, Object?> frozenFields() => <String, Object?>{
    'id': id,
    'sealedAt': sealedAt,
    'compatibility': compatibility,
    'payloadByteLength': payloadByteLength,
    'presentationContract': presentationContract,
    'diagnostic': diagnostic,
    'omittedBytes': omittedBytes,
    'kind': kind,
    'status': status,
    'text': text,
    'channel': channel,
    'details': [for (final value in details) value.toJson()],
    'attachments': [
      for (final value in attachments)
        <String, Object?>{
          'id': value.id,
          'modality': value.modality,
          'filename': value.filename,
          'byteSize': value.byteSize,
          'source': value.source,
        },
    ],
    'tool': tool == null
        ? null
        : <String, Object?>{
            'name': tool!.name,
            'status': tool!.status,
            'callId': tool!.callId,
            'arguments': tool!.arguments,
            'result': tool!.result,
            'progressBytes': tool!.progressBytes,
            'presentationContract': tool!.presentationContract,
            'denialReason': tool!.denialReason,
            'workingDirectory': tool!.workingDirectory,
            'exitCode': tool!.exitCode,
            'attachments': [
              for (final value in tool!.attachments)
                <String, Object?>{
                  'id': value.id,
                  'modality': value.modality,
                  'filename': value.filename,
                  'byteSize': value.byteSize,
                  'source': value.source,
                },
            ],
          },
    'userInput': userInput == null
        ? null
        : <String, Object?>{
            'interactionId': userInput!.interactionId,
            'state': userInput!.state,
            'isPlanConfirmation': userInput!.isPlanConfirmation,
            'planDecision': userInput!.planDecision,
          },
    'plan': plan?.toJson(),
  };
}

final class TimelinePlanObservation {
  const TimelinePlanObservation._({
    required this.interactionId,
    required this.decision,
    required this.documentVersion,
    required this.contentHash,
    required this.document,
    required this.feedback,
  });

  static TimelinePlanObservation _parse(Map<String, dynamic> map) {
    final decision = _string(map, 'decision', 'timeline plan');
    if (!const {
      'approved',
      'revisionRequested',
      'cancelled',
      'resolved',
    }.contains(decision)) {
      throw StateError('unknown completed Plan decision: $decision');
    }
    return TimelinePlanObservation._(
      interactionId: _string(map, 'interactionId', 'timeline plan'),
      decision: decision,
      documentVersion: _intOrNull(map, 'documentVersion', 'timeline plan'),
      contentHash: _requiredStringOrNull(map, 'contentHash', 'timeline plan'),
      document: _requiredStringOrNull(map, 'document', 'timeline plan'),
      feedback: _requiredStringOrNull(map, 'feedback', 'timeline plan'),
    );
  }

  final String interactionId;
  final String decision;
  final int? documentVersion;
  final String? contentHash;
  final String? document;
  final String? feedback;

  Map<String, Object?> toJson() => {
    'interactionId': interactionId,
    'decision': decision,
    'documentVersion': documentVersion,
    'contentHash': contentHash,
    'document': document,
    'feedback': feedback,
  };
}

final class TimelineDetailObservation {
  const TimelineDetailObservation._({
    required this.field,
    required this.totalBytes,
    required this.previewBytes,
  });

  static TimelineDetailObservation _parse(Map<String, dynamic> map) =>
      TimelineDetailObservation._(
        field: _string(map, 'field', 'timeline detail'),
        totalBytes: _int(map, 'totalBytes', 'timeline detail'),
        previewBytes: _int(map, 'previewBytes', 'timeline detail'),
      );

  final String field;
  final int totalBytes;
  final int previewBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'field': field,
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
    required this.presentationContract,
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
      presentationContract: _string(
        map,
        'presentationContract',
        'timeline tool',
      ),
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
  final String presentationContract;
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
  if (value is! int) throw StateError('$owner.$key is not an integer: $value');
  return value;
}

int? _intOrNull(Map<String, dynamic> map, String key, String owner) {
  final value = map[key];
  if (value == null) return null;
  if (value is! int) throw StateError('$owner.$key is not an integer: $value');
  return value;
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
