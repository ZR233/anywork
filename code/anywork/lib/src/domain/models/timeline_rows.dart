import 'package:anywork_client/models.dart';

import '../../shared/typed_json.dart';

enum TimelineRowType {
  userMessage,
  parentAgentMessage,
  commentary,
  finalAnswer,
  activityGroup,
  imageRead,
  imageCard,
  contextCompaction,
  skillActivation,
  agentActivity,
  turnOutcome,
  userInput,
}

/// 当前窗口的不可变呈现投影。每个封闭变体拥有渲染所需的必需载荷。
sealed class TimelineRow {
  const TimelineRow();
  String get id;
  String get threadId;
  String? get turnId;
  DateTime get createdAt;
  int get order;
  int get sequence => order;
  int get renderVersion;
  TimelineRowType get type;
  bool get saved;
  bool get isRolledBack;
  TimelineEntry? get part => null;
  ThreadRawItemStateView? get raw => null;
  Iterable<TimelineEntry> get entries;
  Iterable<TimelineToolItem> get tools => entries
      .where((part) => part.type == TimelineEntryType.tool)
      .map((part) => TimelineToolItem(part: part));
  bool get isPrompt =>
      type == TimelineRowType.userMessage ||
      type == TimelineRowType.parentAgentMessage;
  bool get isCompactActivity => switch (type) {
    TimelineRowType.activityGroup ||
    TimelineRowType.imageRead ||
    TimelineRowType.contextCompaction ||
    TimelineRowType.skillActivation ||
    TimelineRowType.agentActivity => true,
    _ => false,
  };
}

sealed class TimelineItemRow extends TimelineRow {
  const TimelineItemRow({required this.item, required this.part});
  final ThreadItemView item;
  @override
  final TimelineEntry part;
  @override
  String get id => item.id;
  @override
  String get threadId => item.threadId;
  @override
  String get turnId => item.turnId;
  @override
  DateTime get createdAt => item.createdAt;
  @override
  int get order => item.ordinal;
  @override
  int get renderVersion => Object.hash(identityHashCode(part), item.saved);
  @override
  bool get saved => item.saved;
  @override
  bool get isRolledBack =>
      part.contextDisposition == ThreadContextDisposition.rolledBack;
  @override
  Iterable<TimelineEntry> get entries => [part];
}

final class TimelineTextRow extends TimelineItemRow {
  const TimelineTextRow({required super.item, required super.part});
  @override
  TimelineRowType get type => switch (part.textChannel) {
    TimelineTextChannel.user => TimelineRowType.userMessage,
    TimelineTextChannel.parentAgent => TimelineRowType.parentAgentMessage,
    TimelineTextChannel.commentary => TimelineRowType.commentary,
    _ => TimelineRowType.finalAnswer,
  };
}

final class TimelineRawRow extends TimelineItemRow {
  const TimelineRawRow({
    required super.item,
    required super.part,
    required this.record,
  });
  final ThreadRawItemStateView record;
  @override
  ThreadRawItemStateView get raw => record;
  @override
  TimelineRowType get type => TimelineRowType.finalAnswer;
}

final class TimelineSkillRow extends TimelineItemRow {
  const TimelineSkillRow({
    required super.item,
    required super.part,
    required this.activation,
  });
  final TimelineSkillActivation activation;
  @override
  TimelineRowType get type => TimelineRowType.skillActivation;
}

final class TimelineImageRow extends TimelineItemRow {
  const TimelineImageRow({required super.item, required super.part});
  @override
  TimelineRowType get type => TimelineRowType.imageRead;
  TimelineToolItem get tool => TimelineToolItem(part: part);
}

/// 展示工具的图片卡片：一条 `show_image` 调用独立成行。
///
/// 行只携带展示属性——所属工具条目与模型给出的说明文案；图片字节始终由 Thread 附件
/// 缓存按 typed 附件身份读取，行模型不持有字节，也不改写工具条目本身
/// （design/25 §25.6）。
final class TimelineImageCardRow extends TimelineItemRow {
  const TimelineImageCardRow({
    required super.item,
    required super.part,
    required this.caption,
  });

  /// canonical 工具参数里的展示文案；缺失、非字符串或空文本时为 `null`。
  final String? caption;

  @override
  TimelineRowType get type => TimelineRowType.imageCard;

  TimelineToolItem get tool => TimelineToolItem(part: part);
}

final class TimelineCompactionRow extends TimelineItemRow {
  const TimelineCompactionRow({
    required super.item,
    required super.part,
    required this.compaction,
  });
  final ThreadContextCompactionItemStateView compaction;
  @override
  TimelineRowType get type => TimelineRowType.contextCompaction;
}

final class TimelineAgentRow extends TimelineItemRow {
  const TimelineAgentRow({
    required super.item,
    required super.part,
    required this.agent,
  });
  final ThreadAgentItemStateView agent;
  @override
  TimelineRowType get type => TimelineRowType.agentActivity;
}

/// 普通问答回执：一条工具条目携带的只读问答历史独立成行。
///
/// 它保留原工具条目的身份、序位与保存水位，只把 typed 问答投影交给 Timeline 呈现；
/// 不解析工具载荷，也不合成新的回答账本。
final class TimelineUserInputRow extends TimelineItemRow {
  const TimelineUserInputRow({
    required super.item,
    required super.part,
    required this.history,
  });

  final ThreadToolUserInputView history;

  @override
  TimelineRowType get type => TimelineRowType.userInput;

  TimelineToolItem get tool => TimelineToolItem(part: part);
}

final class TimelineOutcomeRow extends TimelineItemRow {
  const TimelineOutcomeRow({
    required super.item,
    required super.part,
    required this.reason,
  });
  final String reason;
  @override
  String get id => 'turn-outcome:${item.id}';
  @override
  TimelineRowType get type => TimelineRowType.turnOutcome;
}

final class TimelineActivityRow extends TimelineRow {
  const TimelineActivityRow(this.group);
  final TimelineActivityGroup group;
  @override
  String get id => group.id;
  @override
  String get threadId => group.parts.first.threadId;
  @override
  String get turnId => group.parts.first.turnId;
  @override
  DateTime get createdAt => group.parts.first.createdAt!;
  @override
  int get order => group.parts.first.order;
  @override
  int get renderVersion => group.renderVersion;
  @override
  TimelineRowType get type => TimelineRowType.activityGroup;
  @override
  bool get saved => group.saved;
  @override
  bool get isRolledBack => group.parts.every(
    (part) => part.contextDisposition == ThreadContextDisposition.rolledBack,
  );
  @override
  Iterable<TimelineEntry> get entries => group.parts;
}

final class TimelineToolItem {
  const TimelineToolItem({required this.part});
  final TimelineEntry part;
  TimelineToolPart? get tool => part.tool;
  String get id => part.id;
  String get name => tool?.name ?? '';
  String get status => part.status;
  String get summary => _commandSummary(tool?.arguments ?? '') ?? '';
}

final class TimelineActivityGroup {
  TimelineActivityGroup({
    required List<TimelineEntry> parts,
    required this.saved,
  }) : parts = List.unmodifiable(parts);
  final List<TimelineEntry> parts;
  final bool saved;
  String get id => 'activity-group:${parts.first.turnId}:${parts.first.id}';
  Iterable<TimelineToolItem> get tools => parts
      .where((part) => part.type == TimelineEntryType.tool)
      .map((part) => TimelineToolItem(part: part));
  int get toolCount => tools.length;
  bool get hasReasoning =>
      parts.any((part) => part.type == TimelineEntryType.reasoning);
  bool get isActive =>
      parts.any((part) => !isTerminalTimelineStatus(part.status));
  TimelineEntry? get firstIssue =>
      parts.where((part) => _activityIssue(part.status)).firstOrNull;
  TimelineEntry get current =>
      parts.where((part) => part.status == 'awaitingApproval').firstOrNull ??
      parts.reversed.firstWhere(
        (part) => !isTerminalTimelineStatus(part.status),
        orElse: () => parts.last,
      );
  int get renderVersion =>
      Object.hashAll([saved, for (final part in parts) identityHashCode(part)]);
}

bool _activityIssue(String status) => const {
  'failed',
  'denied',
  'cancelled',
  'interrupted',
  'budgetLimited',
}.contains(status);

List<TimelineRow> timelineRowsFromThreadItems(List<ThreadItemView> source) =>
    TimelineRowProjector().project(source);

/// 窗口已按 canonical ordinal 有序；仅转换变化条目，按原始顺序一次形成可见行。
final class TimelineRowProjector {
  final Map<String, (ThreadItemView, TimelineEntry)> _entries = {};
  Map<String, TimelineRow> _rows = {};
  List<ThreadItemView> _lastItems = const [];
  List<TimelineRow> _lastRows = const [];

  List<TimelineRow> project(List<ThreadItemView> source) {
    bool sameItem(ThreadItemView a, ThreadItemView b) =>
        identical(a, b) ||
        (a.id == b.id &&
            a.threadId == b.threadId &&
            a.createdAt == b.createdAt &&
            a.executionTerminal == b.executionTerminal &&
            a.revision == b.revision &&
            identical(a.state, b.state) &&
            a.saved == b.saved &&
            a.bodyOmittedUnits == b.bodyOmittedUnits &&
            a.ordinal == b.ordinal &&
            a.turnId == b.turnId &&
            a.updatedAt == b.updatedAt &&
            a.contextDisposition == b.contextDisposition);
    if (source.length == _lastItems.length &&
        source.indexed.every(
          (entry) => sameItem(entry.$2, _lastItems[entry.$1]),
        )) {
      return _lastRows;
    }
    final nextEntries = <String, (ThreadItemView, TimelineEntry)>{};
    for (final item in source) {
      final cached = _entries[item.id];
      nextEntries[item.id] = cached != null && sameItem(cached.$1, item)
          ? cached
          : (item, timelineEntryFromThreadItem(item));
    }
    final nextRows = <String, TimelineRow>{};
    final result = <TimelineRow>[];
    void add(TimelineRow row) {
      final previous = _rows[row.id];
      final oldEntries = previous?.entries.toList();
      final newEntries = row.entries.toList();
      final reusable =
          previous != null &&
          previous.runtimeType == row.runtimeType &&
          previous.saved == row.saved &&
          previous.order == row.order &&
          oldEntries!.length == newEntries.length &&
          oldEntries.indexed.every(
            (entry) => identical(entry.$2, newEntries[entry.$1]),
          );
      final value = reusable ? previous : row;
      nextRows[row.id] = value;
      result.add(value);
    }

    final activities = <TimelineEntry>[];
    var activitySaved = true;
    void flush() {
      if (activities.isEmpty) return;
      add(
        TimelineActivityRow(
          TimelineActivityGroup(parts: activities, saved: activitySaved),
        ),
      );
      activities.clear();
      activitySaved = true;
    }

    for (final item in source) {
      final part = nextEntries[item.id]!.$2;
      if (activities.isNotEmpty && activities.last.turnId != item.turnId) {
        flush();
      }
      if (item.state is ThreadTurnItemStateView) {
        final reason = item.error;
        if (item.isTerminal && reason != null && reason.isNotEmpty) {
          flush();
          add(TimelineOutcomeRow(item: item, part: part, reason: reason));
        }
        continue;
      }
      final ordinaryTool =
          item.kind == ThreadItemKind.toolCall &&
          item.tool?.name != 'view_image';
      // 展示工具是独立图片卡片行：它先结束当前活动组，不并入普通工具摘要。
      if (item.kind == ThreadItemKind.toolCall &&
          item.tool?.name == 'show_image') {
        flush();
        add(
          TimelineImageCardRow(
            item: item,
            part: part,
            caption: _imageCardCaption(item.tool?.arguments ?? ''),
          ),
        );
      } else if (item.tool?.userInput case final userInput?) {
        // 携带 typed 问答历史的工具是独立回执：它先结束当前活动组，不并入普通工具摘要。
        flush();
        add(TimelineUserInputRow(item: item, part: part, history: userInput));
      } else if (item.kind == ThreadItemKind.reasoning || ordinaryTool) {
        activities.add(part);
        activitySaved = activitySaved && item.saved;
      } else if (!const {
        ThreadItemKind.turn,
        ThreadItemKind.inference,
        ThreadItemKind.file,
      }.contains(item.kind)) {
        flush();
        add(switch (item.state) {
          ThreadTextItemStateView() => TimelineTextRow(item: item, part: part),
          final ThreadRawItemStateView raw => TimelineRawRow(
            item: item,
            part: part,
            record: raw,
          ),
          ThreadToolItemStateView() => TimelineImageRow(item: item, part: part),
          final ThreadAgentItemStateView agent => TimelineAgentRow(
            item: item,
            part: part,
            agent: agent,
          ),
          final ThreadContextCompactionItemStateView compaction =>
            TimelineCompactionRow(
              item: item,
              part: part,
              compaction: compaction,
            ),
          ThreadSkillItemStateView() => TimelineSkillRow(
            item: item,
            part: part,
            activation: part.skill!,
          ),
          _ => throw StateError(
            'Unsupported visible timeline item: ${item.kind}',
          ),
        });
      }
    }
    flush();
    _entries
      ..clear()
      ..addAll(nextEntries);
    _rows = nextRows;
    _lastItems = List.unmodifiable(source);
    _lastRows = List.unmodifiable(result);
    return _lastRows;
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

/// `show_image` 卡片的展示文案上限；与工具后端的参数上限一致。
///
/// 超出上限的参数在后端会被拒绝，因此走到这里的超长值只可能来自历史或非 canonical
/// 输入；截断比整段展示更安全，也不改变参数本身。
const _imageCardCaptionLimit = 240;

/// 从 canonical 工具参数里读取展示文案。
///
/// 参数跨供应商边界以文本进入，可能缺失、非对象或不是字符串：这几种情况都返回
/// `null`，卡片因此不占位，也不抛异常。不从 opaque 工具回执里猜测文案。
String? _imageCardCaption(String arguments) {
  final value = decodeJsonObject(arguments)['caption'];
  if (value is! String) {
    return null;
  }
  final caption = value.trim();
  if (caption.isEmpty) {
    return null;
  }
  final runes = caption.runes;
  return runes.length <= _imageCardCaptionLimit
      ? caption
      : String.fromCharCodes(runes.take(_imageCardCaptionLimit));
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
