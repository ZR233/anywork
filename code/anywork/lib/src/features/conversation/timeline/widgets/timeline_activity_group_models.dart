import 'dart:collection';

import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart';

/// 工作组内单条被截断字段的详情引用（纯组件自有不可变值）。
@immutable
final class TimelineActivityDetailRef {
  const TimelineActivityDetailRef({required this.itemId, required this.field});

  final String itemId;
  final ThreadContentFieldView field;

  @override
  bool operator ==(Object other) =>
      other is TimelineActivityDetailRef &&
      other.itemId == itemId &&
      other.field == field;

  @override
  int get hashCode => Object.hash(itemId, field);
}

/// 工具调用终态分类（工作组组件只接受已完成项）。
enum TimelineToolGroupOutcome {
  succeeded,
  failed,
  cancelled,
  interrupted,
  rejected,
}

/// 思考与工具工作组组件唯一接受的封闭消息基类。
///
/// 采用 `sealed` 限定工作组只接受组内合法的已完成活动类型：
/// - [TimelineThinkingGroupMessage]（思考消息）
/// - [TimelineToolGroupMessage]（工具调用消息，含 `wait` / `sleep`）
/// - [TimelineSkillGroupMessage]（技能加载消息）
///
/// 会话（`threadId`）、轮次（`turnId`）以及何时切换新工作组由上层派发方决定；
/// 工作组组件自身不感知轮次，也不接受用户消息、助手回复正文、轮次状态、原始记录、
/// 问答/计划回执、连续读图图集等工作组外类型。
@immutable
sealed class TimelineActivityGroupMessage {
  const TimelineActivityGroupMessage({
    required this.id,
    required this.createdAt,
    required this.completedAt,
    this.order = 0,
    this.rolledBack = false,
    this.details = const [],
    this.bodyUnavailable = false,
  });

  final String id;
  final int order;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final bool rolledBack;
  final List<TimelineActivityDetailRef> details;
  final bool bodyUnavailable;

  Duration? get duration {
    final start = createdAt;
    final end = completedAt;
    return start == null || end == null || end.isBefore(start)
        ? null
        : end.difference(start);
  }
}

/// 1. 组内已完成思考消息。
final class TimelineThinkingGroupMessage extends TimelineActivityGroupMessage {
  const TimelineThinkingGroupMessage({
    required super.id,
    required super.createdAt,
    required super.completedAt,
    this.error,
    this.cancelled = false,
    this.summary = '',
    this.content = '',
    this.summaryChunks = const [],
    super.order,
    super.rolledBack,
    super.details,
    super.bodyUnavailable,
  });

  final String? error;
  final bool cancelled;

  /// 最新思考概要（Markdown 文本）。
  final String summary;

  /// 完整思考推理正文（Markdown 文本，可为空）。
  final String content;

  /// 可选的多段概要分块（若为空则由 [summary] 派生单段）。
  final List<String> summaryChunks;

  List<String> get effectiveSummaryChunks {
    final chunks = summaryChunks
        .map((chunk) => chunk.trim())
        .where((chunk) => chunk.isNotEmpty)
        .toList(growable: false);
    if (chunks.isNotEmpty) return chunks;
    final trimmed = summary.trim();
    return trimmed.isEmpty ? const [] : [trimmed];
  }

  String? get latestSummary => effectiveSummaryChunks.lastOrNull;

  bool get hasSummary => effectiveSummaryChunks.isNotEmpty;

  bool get hasContent => content.trim().isNotEmpty;

  bool get hasNotice => details.isNotEmpty || bodyUnavailable;

  /// 仅含概要（无思考正文且无截断详情）时不做二次展开能力。
  bool get isExpandable => hasContent || hasNotice;
}

/// 2. 组内已完成工具调用消息（含普通工具与 `wait` / `sleep` 等待工具）。
final class TimelineToolGroupMessage extends TimelineActivityGroupMessage {
  const TimelineToolGroupMessage({
    required super.id,
    required super.createdAt,
    required super.completedAt,
    required this.toolCallId,
    required this.name,
    this.arguments = '{}',
    this.output = '',
    this.outcome = TimelineToolGroupOutcome.succeeded,
    this.error,
    this.outputArtifacts = const [],
    this.wait,
    this.taskId,
    this.workingDirectory,
    this.exitCode,
    this.timedOut = false,
    this.attachments = const [],
    super.order,
    super.rolledBack,
    super.details,
    super.bodyUnavailable,
  });

  final String toolCallId;
  final String name;
  final String arguments;
  final String output;
  final TimelineToolGroupOutcome outcome;
  final String? error;
  final List<String> outputArtifacts;
  final ThreadWaitPresentationView? wait;
  final String? taskId;
  final String? workingDirectory;
  final int? exitCode;
  final bool timedOut;
  final List<ThreadAttachmentView> attachments;

  bool get isIssue =>
      outcome == TimelineToolGroupOutcome.failed ||
      outcome == TimelineToolGroupOutcome.rejected;

  String get statusString => switch (outcome) {
    TimelineToolGroupOutcome.succeeded => 'succeeded',
    TimelineToolGroupOutcome.failed => 'failed',
    TimelineToolGroupOutcome.cancelled => 'cancelled',
    TimelineToolGroupOutcome.interrupted => 'interrupted',
    TimelineToolGroupOutcome.rejected => 'denied',
  };
}

/// 3. 组内已完成技能加载消息。
final class TimelineSkillGroupMessage extends TimelineActivityGroupMessage {
  const TimelineSkillGroupMessage({
    required super.id,
    required super.createdAt,
    required super.completedAt,
    required this.skillName,
    this.source = 'project',
    this.providerId = 'project',
    this.resourceBase = const SkillResourceBaseView(
      SkillResourceBaseKind.directory,
      '',
    ),
    this.cause = const SkillActivationCauseView(
      SkillActivationCauseKind.userGesture,
      '',
    ),
    super.order,
    super.rolledBack,
    super.details,
    super.bodyUnavailable,
  });

  final String skillName;
  final String source;
  final String providerId;
  final SkillResourceBaseView resourceBase;
  final SkillActivationCauseView cause;
}

/// 思考与工具工作组独立控制器。
///
/// 只接受 [TimelineActivityGroupMessage]（`sealed` 限定思考、工具、技能三类已完成消息）：
/// - 支持通过 [add] / [addAll] 持续向组内添加已完成活动消息；
/// - 轮次与何时新建工作组由上层派发方决定，控制器本身不感知轮次；
/// - 自动配对组内成功的 `skill_view` 工具调用与 [TimelineSkillGroupMessage]，
///   并静态计算整组工作时长 [elapsedDuration] 与工具/技能计数。
class TimelineActivityGroupController extends ChangeNotifier {
  TimelineActivityGroupController({
    this.id = 'activity-group',
    bool initiallyExpanded = false,
    Iterable<TimelineActivityGroupMessage> initialMessages = const [],
  }) : _expanded = initiallyExpanded {
    addAll(initialMessages);
  }

  final String id;
  bool _expanded;
  final List<TimelineActivityGroupMessage> _messages = [];
  final Map<String, String> _skillToToolId = {};
  final Set<String> _hiddenToolIds = {};

  bool get expanded => _expanded;

  void setExpanded(bool value) {
    if (_expanded == value) return;
    _expanded = value;
    notifyListeners();
  }

  bool get isEmpty => _messages.isEmpty;
  int get length => _messages.length;

  UnmodifiableListView<TimelineActivityGroupMessage> get messages =>
      UnmodifiableListView(_messages);

  /// 可见成员列表（已将配对成功的 `skill_view` 工具调用合并到对应技能行中）。
  List<TimelineActivityGroupMessage> get visibleMessages => [
    for (final message in _messages)
      if (!_hiddenToolIds.contains(message.id)) message,
  ];

  /// 整个工作组从最早成员创建到最晚成员完成的总工作时长。
  Duration? get elapsedDuration {
    if (_messages.isEmpty) return null;
    DateTime? earliestStart;
    DateTime? latestEnd;
    for (final message in _messages) {
      final start = message.createdAt;
      final end = message.completedAt;
      if (start == null || end == null) return null;
      if (earliestStart == null || start.isBefore(earliestStart)) {
        earliestStart = start;
      }
      if (latestEnd == null || end.isAfter(latestEnd)) {
        latestEnd = end;
      }
    }
    if (earliestStart == null ||
        latestEnd == null ||
        latestEnd.isBefore(earliestStart)) {
      return null;
    }
    return latestEnd.difference(earliestStart);
  }

  int get thinkingCount =>
      _messages.whereType<TimelineThinkingGroupMessage>().length;

  int get skillCount => _messages.whereType<TimelineSkillGroupMessage>().length;

  int get toolCount => _messages
      .whereType<TimelineToolGroupMessage>()
      .where((tool) => !_hiddenToolIds.contains(tool.id))
      .length;

  int get issueCount => _messages
      .whereType<TimelineToolGroupMessage>()
      .where((tool) => !_hiddenToolIds.contains(tool.id) && tool.isIssue)
      .length;

  /// 单成员纯思考组在概要、正文与截断详情均为空时不承诺空的展开区。
  bool get isExpandable {
    if (_messages.isEmpty) return false;
    if (_messages.length == 1 &&
        _messages.single is TimelineThinkingGroupMessage) {
      final thinking = _messages.single as TimelineThinkingGroupMessage;
      return thinking.hasSummary || thinking.hasContent || thinking.hasNotice;
    }
    return true;
  }

  TimelineToolGroupMessage? pairedToolFor(TimelineSkillGroupMessage skill) {
    final toolId = _skillToToolId[skill.id];
    if (toolId == null) return null;
    for (final message in _messages) {
      if (message is TimelineToolGroupMessage && message.id == toolId) {
        return message;
      }
    }
    return null;
  }

  /// 向工作组持续添加一条已完成 [TimelineActivityGroupMessage]（同 `id` 幂等替换）。
  ///
  /// 返回 `true` 表示替换了已存在的同 `id` 消息，返回 `false` 表示新增消息。
  bool add(TimelineActivityGroupMessage message) {
    final existingIndex = _messages.indexWhere((m) => m.id == message.id);
    final replaced = existingIndex >= 0;
    if (replaced) {
      _messages[existingIndex] = message;
    } else {
      _messages.add(message);
      _messages.sort(_compareMessages);
    }
    _recomputeSkillPairs();
    notifyListeners();
    return replaced;
  }

  /// 批量向工作组添加已完成 [TimelineActivityGroupMessage]。
  void addAll(Iterable<TimelineActivityGroupMessage> messages) {
    var changed = false;
    for (final message in messages) {
      final existingIndex = _messages.indexWhere((m) => m.id == message.id);
      if (existingIndex >= 0) {
        _messages[existingIndex] = message;
      } else {
        _messages.add(message);
      }
      changed = true;
    }
    if (!changed) return;
    _messages.sort(_compareMessages);
    _recomputeSkillPairs();
    notifyListeners();
  }

  static int _compareMessages(
    TimelineActivityGroupMessage a,
    TimelineActivityGroupMessage b,
  ) {
    if (a.order != b.order) return a.order.compareTo(b.order);
    return a.id.compareTo(b.id);
  }

  void _recomputeSkillPairs() {
    _skillToToolId.clear();
    _hiddenToolIds.clear();
    final toolsByCallId = <String, TimelineToolGroupMessage>{};
    for (final message in _messages) {
      if (message is TimelineToolGroupMessage &&
          message.name == 'skill_view' &&
          message.outcome == TimelineToolGroupOutcome.succeeded) {
        toolsByCallId[message.toolCallId] = message;
      }
    }
    for (final message in _messages) {
      if (message is TimelineSkillGroupMessage &&
          message.cause.kind == SkillActivationCauseKind.tool) {
        final tool = toolsByCallId[message.cause.id];
        if (tool != null && !_hiddenToolIds.contains(tool.id)) {
          _skillToToolId[message.id] = tool.id;
          _hiddenToolIds.add(tool.id);
        }
      }
    }
  }
}
