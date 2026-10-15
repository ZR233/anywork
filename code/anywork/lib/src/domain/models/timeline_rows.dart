// The row projection is app-owned: the Client no longer provides `TimelineRow`
// or `TimelineRowProjector`.
import 'package:anywork_client/models.dart';

import '../../shared/typed_json.dart';

/// 展示行的类型。行类型只描述「这一行是什么」，具体渲染由 feature 层的内容组件承担。
enum TimelineRowType {
  userMessage,
  parentAgentMessage,
  commentary,
  toolGroup,
  reasoningSummary,
  skillActivation,
  agentActivity,
  finalAnswer,
  turnOutcome,
}

/// 一条 Timeline 展示行。
///
/// 行是窗口条目的**显示投影**，不是第二份正文事实源：正文、状态与省略量都由 canonical
/// 窗口条目携带。身份取自行身份（条目 id、分组合成 id、终态合成 id），不以正文、随机数或
/// 时间生成。`renderVersion` 只表达「这一行的可见内容是否变化」，供消息集合判定原位更新。
class TimelineRow {
  const TimelineRow._({
    required this.id,
    required this.threadId,
    required this.type,
    required this.createdAt,
    required this.order,
    required this.sequence,
    required this.renderVersion,
    this.turnId,
    this.part,
    this.raw,
    this.toolGroup,
    this.reasoningGroup,
    this.agentEvent,
    this.isRolledBack = false,
    this.saved = true,
  });

  factory TimelineRow.item({
    required ThreadItemView item,
    required TimelineEntry part,
    required TimelineRowType type,
  }) {
    return TimelineRow._(
      id: item.id,
      threadId: item.threadId,
      type: type,
      createdAt: item.createdAt,
      order: item.ordinal,
      sequence: item.ordinal,
      renderVersion: Object.hash(timelineRowRenderVersion(part), item.saved),
      turnId: item.turnId,
      part: part,
      raw: item.state is ThreadRawItemStateView
          ? item.state as ThreadRawItemStateView
          : null,
      isRolledBack:
          part.contextDisposition == ThreadContextDisposition.rolledBack,
      saved: item.saved,
    );
  }

  factory TimelineRow.turnOutcome(ThreadItemView item, int lastOrdinal) {
    final part = timelineEntryFromThreadItem(item);
    return TimelineRow._(
      id: 'turn-outcome:${item.id}',
      threadId: item.threadId,
      type: TimelineRowType.turnOutcome,
      createdAt: item.updatedAt,
      order: lastOrdinal + 1,
      sequence: lastOrdinal,
      renderVersion: Object.hash(timelineRowRenderVersion(part), item.saved),
      turnId: item.turnId,
      part: part,
      saved: item.saved,
    );
  }

  factory TimelineRow.agentActivity(TimelineAgentEvent event) {
    return TimelineRow._(
      id: 'agent-activity:${timelineAgentEventGroupKey(event)}',
      threadId: event.threadId,
      type: TimelineRowType.agentActivity,
      createdAt: event.createdAt,
      order: 0,
      sequence: event.sequence,
      renderVersion: timelineAgentEventRenderVersion(event),
      agentEvent: event,
    );
  }

  factory TimelineRow.toolGroup(TimelineToolGroup group) {
    return TimelineRow._(
      id: group.id,
      threadId: group.threadId,
      type: TimelineRowType.toolGroup,
      createdAt: group.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      order: group.order,
      sequence: group.sequence,
      renderVersion: group.renderVersion,
      turnId: group.turnId,
      toolGroup: group,
      isRolledBack: group.isRolledBack,
    );
  }

  factory TimelineRow.reasoningGroup(TimelineReasoningGroup group) {
    return TimelineRow._(
      id: group.id,
      threadId: group.threadId,
      type: TimelineRowType.reasoningSummary,
      createdAt: group.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
      order: group.order,
      sequence: group.sequence,
      renderVersion: group.renderVersion,
      turnId: group.turnId,
      reasoningGroup: group,
      isRolledBack: group.isRolledBack,
    );
  }

  final String id;
  final String threadId;
  final TimelineRowType type;
  final DateTime createdAt;
  final int order;
  final int sequence;
  final int renderVersion;
  final String? turnId;
  final TimelineEntry? part;
  final ThreadRawItemStateView? raw;
  final TimelineToolGroup? toolGroup;
  final TimelineReasoningGroup? reasoningGroup;
  final TimelineAgentEvent? agentEvent;
  final bool isRolledBack;
  final bool saved;

  bool get isPrompt =>
      type == TimelineRowType.userMessage ||
      type == TimelineRowType.parentAgentMessage;

  bool get isCompactActivity =>
      type == TimelineRowType.reasoningSummary ||
      type == TimelineRowType.toolGroup ||
      type == TimelineRowType.skillActivation;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TimelineRow &&
            id == other.id &&
            threadId == other.threadId &&
            type == other.type &&
            createdAt == other.createdAt &&
            order == other.order &&
            sequence == other.sequence &&
            renderVersion == other.renderVersion &&
            turnId == other.turnId &&
            isRolledBack == other.isRolledBack &&
            saved == other.saved;
  }

  @override
  int get hashCode => Object.hash(
    id,
    threadId,
    type,
    createdAt,
    order,
    sequence,
    renderVersion,
    turnId,
    isRolledBack,
    saved,
  );
}

List<TimelineRow> timelineRowsFromThreadItems(
  List<ThreadItemView> source, {
  Map<String, TimelineTurnView> turns = const {},
}) {
  return TimelineRowProjector().project(source, turns: turns);
}

/// 把有界窗口条目投影成显示行，并按条目复用转换结果。
///
/// 逐帧重算整窗投影的代价随窗口增长：流式增量只改变一条条目，但整窗重排、重新构造
/// `TimelineEntry`（含把全部推理分块拼成一整段字符串）与重建分组都会跟着发生。
/// 这里按条目身份 + 内容身份缓存转换结果：**只有真正变化的条目**重新转换，其余复用上一步的
/// 对象。投影在结构（身份序列）不变时直接复用上一步的行列表。
class TimelineRowProjector {
  TimelineRowProjector();

  final Map<String, _ProjectedEntry> _entries = {};

  /// 行对象按 (身份, renderVersion) 驻留：版本没变就复用**同一个行对象**。
  final Map<(String, int), TimelineRow> _rowsByVersion = {};
  List<String>? _lastIds;
  Map<String, TimelineTurnView>? _lastTurns;
  List<TimelineRow>? _lastRows;

  /// 把窗口条目投影成显示行。
  ///
  /// 身份序列与轮次事实都没变、且每条条目的内容身份一致时，直接复用上一次的行列表；
  /// 否则只重新转换内容真正变化的条目，其余复用缓存对象。
  List<TimelineRow> project(
    List<ThreadItemView> source, {
    Map<String, TimelineTurnView> turns = const {},
  }) {
    final sorted = [...source]
      ..sort((left, right) {
        final ordinal = left.ordinal.compareTo(right.ordinal);
        return ordinal != 0 ? ordinal : left.id.compareTo(right.id);
      });
    if (_matchesLastInput(sorted, turns)) return _lastRows!;
    final entries = <String, TimelineEntry>{};
    final next = <String, _ProjectedEntry>{};
    for (final item in sorted) {
      final projected = _project(item);
      entries[item.id] = projected.entry;
      next[item.id] = projected;
    }
    final rows = _rowsFrom(sorted, entries, turns);
    _entries
      ..clear()
      ..addAll(next);
    _lastIds = [for (final item in sorted) item.id];
    _lastTurns = turns;
    _lastRows = rows;
    return rows;
  }

  bool _matchesLastInput(
    List<ThreadItemView> sorted,
    Map<String, TimelineTurnView> turns,
  ) {
    final ids = _lastIds;
    if (ids == null || ids.length != sorted.length) return false;
    if (!identical(_lastTurns, turns)) return false;
    for (var index = 0; index < sorted.length; index++) {
      final item = sorted[index];
      if (ids[index] != item.id) return false;
      final cached = _entries[item.id];
      if (cached == null || cached.signature != _signature(item)) return false;
    }
    return true;
  }

  _ProjectedEntry _project(ThreadItemView item) {
    final signature = _signature(item);
    final cached = _entries[item.id];
    if (cached != null && cached.signature == signature) return cached;
    return _ProjectedEntry(
      entry: timelineEntryFromThreadItem(item),
      signature: signature,
    );
  }

  /// 条目内容身份：revision、状态实例、保存水位与各字段的有界指纹。
  static _EntrySignature _signature(ThreadItemView item) {
    return _EntrySignature(
      revision: item.revision,
      state: identityHashCode(item.state),
      saved: item.saved,
      omitted: item.bodyOmittedUnits,
      body: _bodyFingerprint(item.text),
      summary: _listFingerprint(item.reasoningSummary),
      content: _listFingerprint(item.reasoningContent),
    );
  }

  static Object? _listFingerprint(List<String> chunks) {
    if (chunks.isEmpty) return 0;
    return Object.hash(chunks.length, _bodyFingerprint(chunks.last));
  }

  /// 同一行在两个版本之间保持对象身份；版本变化时替换为新的行对象。
  TimelineRow _interned(String id, int version, TimelineRow Function() build) {
    final key = (id, version);
    final cached = _rowsByVersion[key];
    if (cached != null) return cached;
    final row = build();
    _rowsByVersion[key] = row;
    if (_rowsByVersion.length > 1024) {
      // 有界：只保留最近的一批版本，避免长时间会话积累历史行对象。
      for (final stale
          in _rowsByVersion.keys
              .take(_rowsByVersion.length - 512)
              .toList(growable: false)) {
        _rowsByVersion.remove(stale);
      }
    }
    return row;
  }

  List<TimelineRow> _rowsFrom(
    List<ThreadItemView> items,
    Map<String, TimelineEntry> entries,
    Map<String, TimelineTurnView> turns,
  ) {
    final rows = <TimelineRow>[];
    final adjacentTools = <TimelineEntry>[];
    final adjacentReasoning = <TimelineEntry>[];

    void flushTools() {
      if (adjacentTools.isEmpty) return;
      final first = adjacentTools.first;
      final group = TimelineToolGroup(
        id: 'tool-group:${first.turnId}:${first.id}',
        threadId: first.threadId,
        groupId: first.turnId,
        turnId: first.turnId,
        items: [
          for (final part in adjacentTools) TimelineToolGroupItem(part: part),
        ],
      );
      rows.add(
        _interned(
          group.id,
          group.renderVersion,
          () => TimelineRow.toolGroup(group),
        ),
      );
      adjacentTools.clear();
    }

    void flushReasoning() {
      if (adjacentReasoning.isEmpty) return;
      final first = adjacentReasoning.first;
      final group = TimelineReasoningGroup(
        id: 'reasoning-group:${first.turnId}:${first.id}',
        threadId: first.threadId,
        groupId: first.turnId,
        turnId: first.turnId,
        parts: [...adjacentReasoning],
      );
      rows.add(
        _interned(
          group.id,
          group.renderVersion,
          () => TimelineRow.reasoningGroup(group),
        ),
      );
      adjacentReasoning.clear();
    }

    for (final item in items) {
      if (const {
        ThreadItemKind.file,
        ThreadItemKind.turn,
        ThreadItemKind.inference,
        ThreadItemKind.contextCompaction,
      }.contains(item.kind)) {
        continue;
      }
      final part = entries[item.id]!;
      if (item.kind == ThreadItemKind.toolCall) {
        flushReasoning();
        if (adjacentTools.isNotEmpty &&
            adjacentTools.last.turnId != item.turnId) {
          flushTools();
        }
        adjacentTools.add(part);
        continue;
      }
      if (item.kind == ThreadItemKind.reasoning) {
        flushTools();
        if (adjacentReasoning.isNotEmpty &&
            adjacentReasoning.last.turnId != item.turnId) {
          flushReasoning();
        }
        adjacentReasoning.add(part);
        continue;
      }
      rows.add(
        _interned(
          item.id,
          Object.hash(timelineRowRenderVersion(part), item.saved),
          () => TimelineRow.item(
            item: item,
            part: part,
            type: switch (item.kind) {
              ThreadItemKind.raw => TimelineRowType.finalAnswer,
              ThreadItemKind.userMessage => TimelineRowType.userMessage,
              ThreadItemKind.parentAgentMessage =>
                TimelineRowType.parentAgentMessage,
              ThreadItemKind.agentMessage =>
                item.channel == AgentMessageChannel.commentary
                    ? TimelineRowType.commentary
                    : TimelineRowType.finalAnswer,
              ThreadItemKind.skill => TimelineRowType.skillActivation,
              ThreadItemKind.reasoning => TimelineRowType.reasoningSummary,
              ThreadItemKind.toolCall => TimelineRowType.toolGroup,
              ThreadItemKind.agent => TimelineRowType.agentActivity,
              ThreadItemKind.turn ||
              ThreadItemKind.inference ||
              ThreadItemKind.file ||
              ThreadItemKind.contextCompaction => TimelineRowType.finalAnswer,
            },
          ),
        ),
      );
    }
    flushTools();
    flushReasoning();
    final lastOrdinalByTurn = <String, int>{};
    for (final item in items) {
      lastOrdinalByTurn[item.turnId] = item.ordinal;
    }
    for (final item in items) {
      if (item.kind == ThreadItemKind.turn &&
          !turns.containsKey(item.turnId) &&
          item.isTerminal &&
          item.error?.trim().isNotEmpty == true) {
        rows.add(
          TimelineRow.turnOutcome(item, lastOrdinalByTurn[item.turnId]!),
        );
      }
    }
    final byId = {for (final item in items) item.id: item};
    for (final entry in turns.values) {
      final end = byId[entry.lastItemId];
      if (end == null) continue;
      final turn = entry.turn;
      final item = ThreadItemView(
        id: 'turn:${turn.turnId.length}:${turn.turnId}',
        threadId: turn.threadId,
        turnId: turn.turnId,
        ordinal: end.ordinal,
        revision: turn.revision,
        createdAt: turn.updatedAt,
        updatedAt: turn.updatedAt,
        state: ThreadTurnItemStateView(turn.state, inputId: turn.inputId),
      );
      if (item.isTerminal && item.error?.trim().isNotEmpty == true) {
        rows.add(TimelineRow.turnOutcome(item, end.ordinal));
      }
    }
    rows.sort(_compareRows);
    return rows;
  }
}

/// 把一条窗口条目投影为渲染用的 `TimelineEntry`。
TimelineEntry timelineEntryFromThreadItem(ThreadItemView item) {
  final text = switch (item.kind) {
    // 推理正文不做整段拼接：分块原样带给 `reasoningSummary`/`reasoningContent`，渲染与
    // 指纹都由分块列表给出。整窗投影每帧都会走到这里，把每次增量重新拼成一整段字符串
    // 会让热路径随正文长度线性变慢。
    ThreadItemKind.reasoning => '',
    ThreadItemKind.toolCall => _toolActivityText(item.tool),
    _ => item.text,
  };
  return TimelineEntry(
    id: item.id,
    groupId: item.turnId,
    threadId: item.threadId,
    turnId: item.turnId,
    type: switch (item.kind) {
      ThreadItemKind.userMessage ||
      ThreadItemKind.parentAgentMessage ||
      ThreadItemKind.agentMessage ||
      ThreadItemKind.raw => TimelineEntryType.text,
      ThreadItemKind.reasoning => TimelineEntryType.reasoning,
      ThreadItemKind.skill => TimelineEntryType.skill,
      ThreadItemKind.toolCall => TimelineEntryType.tool,
      ThreadItemKind.agent => TimelineEntryType.text,
      ThreadItemKind.turn ||
      ThreadItemKind.inference ||
      ThreadItemKind.file ||
      ThreadItemKind.contextCompaction => TimelineEntryType.file,
    },
    order: item.ordinal,
    sequence: item.ordinal,
    revision: item.revision,
    createdAt: item.createdAt,
    updatedAt: item.updatedAt,
    completedAt: item.completedAt,
    error: item.error,
    text: text,
    reasoningSummary: item.reasoningSummary,
    reasoningContent: item.reasoningContent,
    status: item.status,
    textChannel: switch (item.kind) {
      ThreadItemKind.userMessage => TimelineTextChannel.user,
      ThreadItemKind.parentAgentMessage => TimelineTextChannel.parentAgent,
      ThreadItemKind.agentMessage =>
        item.channel == AgentMessageChannel.commentary
            ? TimelineTextChannel.commentary
            : TimelineTextChannel.finalAnswer,
      _ => null,
    },
    tool: item.tool,
    skill: switch (item.skill) {
      final skill? => TimelineSkillActivation(
        name: skill.name,
        source: skill.source,
        providerId: skill.providerId,
        resourceBase: skill.resourceBase,
        cause: skill.cause,
        activatedAt: skill.activatedAt,
      ),
      null => null,
    },
    attachments: item.attachments,
    contextDisposition: item.contextDisposition,
  );
}

int _compareRows(TimelineRow left, TimelineRow right) {
  final sequence = left.sequence.compareTo(right.sequence);
  if (sequence != 0) return sequence;
  final order = left.order.compareTo(right.order);
  if (order != 0) return order;
  return left.id.compareTo(right.id);
}

/// 单条条目的渲染版本：与行对象的 `renderVersion` 使用同一算法。
int timelineRowRenderVersion(TimelineEntry part) {
  final tool = part.tool;
  return Object.hashAll([
    part.id,
    part.revision,
    part.status,
    _bodyFingerprint(part.text),
    _bodyFingerprint(part.reasoningSummary.join()),
    _bodyFingerprint(part.reasoningContent.join()),
    part.skill?.name,
    part.skill?.source,
    part.skill?.providerId,
    part.skill?.resourceBase.kind,
    part.skill?.resourceBase.value,
    part.skill?.cause.kind,
    part.skill?.cause.id,
    part.contextDisposition,
    part.updatedAt?.millisecondsSinceEpoch,
    part.error,
    _bodyFingerprint(tool?.arguments),
    tool?.taskId,
    _bodyFingerprint(tool?.result),
    tool?.exitCode,
    tool?.timedOut,
    tool?.denialReason,
  ]);
}

/// 一次智能体活动事件的渲染版本。
int timelineAgentEventRenderVersion(TimelineAgentEvent event) {
  return Object.hashAll([
    event.eventId,
    event.sequence,
    event.callId,
    event.title,
    event.text,
    event.status,
    event.payload.runtimeType,
    if (event.payload case TimelineSubAgentActivity(:final timedOut)) timedOut,
    if (event.payload case TimelineTodoListUpdate(:final items))
      for (final item in items) ...[item.step, item.status],
    event.createdAt.millisecondsSinceEpoch,
  ]);
}

/// 正文指纹：长度 + 有界尾部样本。
///
/// 渲染版本只需要「内容变了没有」；对整串取哈希会让大正文在每次投影/增量时都被重新遍历。
Object? _bodyFingerprint(String? text) {
  if (text == null || text.isEmpty) return text;
  final tail = text.length <= 256 ? text : text.substring(text.length - 256);
  return Object.hash(text.length, tail);
}

String? _commandSummary(String arguments) {
  final json = decodeJsonObject(arguments);
  final command = jsonStringValue(json['command']);
  final path =
      jsonStringValue(json['path']) ??
      jsonStringValue(json['filePath']) ??
      jsonStringValue(json['targetPath']) ??
      jsonStringValue(json['workingDirectory']);
  final query = jsonStringValue(json['query']);
  final value = command?.isNotEmpty == true
      ? command!.split('\n').first
      : path?.isNotEmpty == true
      ? path!
      : query;
  return value == null || value.isEmpty ? null : value;
}

String _toolActivityText(TimelineToolPart? tool) {
  if (tool == null) {
    return '';
  }
  return [
    _commandSummary(tool.arguments),
    tool.workingDirectory,
    tool.denialReason,
    tool.result,
  ].whereType<String>().where((value) => value.trim().isNotEmpty).join('\n');
}

/// 一次投影的产物与它的内容身份。
class _ProjectedEntry {
  const _ProjectedEntry({required this.entry, required this.signature});

  final TimelineEntry entry;
  final _EntrySignature signature;
}

/// 条目内容身份；只用于缓存判定，不参与渲染。
class _EntrySignature {
  const _EntrySignature({
    required this.revision,
    required this.state,
    required this.saved,
    required this.omitted,
    required this.body,
    required this.summary,
    required this.content,
  });

  final int revision;
  final int state;
  final bool saved;
  final int omitted;
  final Object? body;
  final Object? summary;
  final Object? content;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _EntrySignature &&
          revision == other.revision &&
          state == other.state &&
          saved == other.saved &&
          omitted == other.omitted &&
          body == other.body &&
          summary == other.summary &&
          content == other.content;

  @override
  int get hashCode =>
      Object.hash(revision, state, saved, omitted, body, summary, content);
}
