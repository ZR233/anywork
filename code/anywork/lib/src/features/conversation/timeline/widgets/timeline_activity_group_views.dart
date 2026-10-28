import 'dart:math' as math;

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_key_values.dart';
import '../../../../shared/studio_driver_keys.dart';
import 'timeline_markdown.dart';
import 'reasoning_summary.dart';
import 'timeline_activity_group_models.dart';
import 'timeline_activity_row.dart';
import 'timeline_wait_blocks.dart';

export 'timeline_activity_group_models.dart';

import 'timeline_tool_blocks.dart';

/// 打开被省略字段完整详情查看器的可选回调。
///
/// 独立预览与纯展示组件无需依赖 `TimelineDisplayLease` 即可渲染思考与工具活动组；
/// 生产 Timeline 传入绑定当前代次 lease 的查看器回调。
typedef TimelineDetailOpenCallback = void Function(
  String itemId,
  ThreadContentFieldView field,
);

/// 独立的思考与工具工作组元素组件。
///
/// 只接受绑定自有的 [TimelineActivityGroupController]（其内部消息严格由封闭类
/// `sealed class` [TimelineActivityGroupMessage] 限定为思考、工具、技能三类已完成项，
/// 不接受任何工作组外类型）：
/// - 顶层折叠行不展示前置图标，汇总整组工作时长与工具/技能调用数量；
/// - 展开后组内思考行展示最新思考概要的 Markdown，仅含概要（无正文与截断详情）的
///   思考消息不提供二次展开能力。
class TimelineActivityGroupBlock extends StatefulWidget {
  const TimelineActivityGroupBlock({
    required this.controller,
    this.onOpenDetail,
    super.key,
  });

  final TimelineActivityGroupController controller;
  final TimelineDetailOpenCallback? onOpenDetail;

  @override
  State<TimelineActivityGroupBlock> createState() =>
      _TimelineActivityGroupBlockState();
}

class _TimelineActivityGroupBlockState
    extends State<TimelineActivityGroupBlock> {
  final ExpansibleController _expansion = ExpansibleController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (widget.controller.expanded && !_expansion.isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.controller.expanded && !_expansion.isExpanded) {
          _expansion.expand();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant TimelineActivityGroupBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _expansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, body) {
        if (controller.isEmpty) return const SizedBox.shrink();
        return Padding(
          key: StudioDriverKeys.timelineRow(controller.id),
          padding: const EdgeInsets.only(bottom: 6),
          child: TimelineActivityTileTheme(
            child: ExpansionTile(
              controller: _expansion,
              initiallyExpanded: controller.expanded,
              onExpansionChanged: controller.setExpanded,
              maintainState: false,
              showTrailingIcon: false,
              minTileHeight: 28,
              dense: true,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 2),
              shape: const Border(),
              collapsedShape: const Border(),
              title: TimelineActivityRow(
                key: StudioDriverKeys.timelineActivitySummary(controller.id),
                label: timelineActivityGroupControllerLabel(
                  context,
                  controller,
                ),
                active: false,
                expanded: controller.expanded,
                expandable: controller.isExpandable,
              ),
              children: [body!],
            ),
          ),
        );
      },
      child: _TimelineActivityControllerContents(
        controller: controller,
        onOpenDetail: widget.onOpenDetail,
      ),
    );
  }
}

/// 面向工作组独立控制器 [TimelineActivityGroupController] 的顶层折叠汇总文案：
/// 展示整组工作时长 + 工具/技能调用数量（无左侧图标）。
String timelineActivityGroupControllerLabel(
  BuildContext context,
  TimelineActivityGroupController controller,
) {
  final counts = [
    if (controller.toolCount > 0)
      controller.issueCount > 0
          ? context.l10n.timelineToolGroupSummaryIssues(
              controller.toolCount,
              controller.issueCount,
            )
          : context.l10n.timelineToolGroupSummary(controller.toolCount),
    if (controller.skillCount > 0)
      context.l10n.statusSkillsCount(controller.skillCount),
  ];
  final onlySkills =
      controller.toolCount == 0 &&
      controller.thinkingCount == 0 &&
      counts.isNotEmpty;
  if (onlySkills) return counts.join(' · ');

  final elapsed = controller.elapsedDuration;
  if (elapsed != null) {
    final worked = groupWorkedLabel(context, elapsed);
    return counts.isEmpty ? worked : '$worked · ${counts.join(' · ')}';
  }

  final title = controller.thinkingCount == 0
      ? context.l10n.timelineToolGroupTitle
      : controller.toolCount > 0 || controller.skillCount > 0
      ? context.l10n.timelineActivityTitle
      : context.l10n.timelineReasoningFallback;
  return counts.isEmpty ? title : '$title · ${counts.join(' · ')}';
}

class _TimelineActivityControllerContents extends StatelessWidget {
  const _TimelineActivityControllerContents({
    required this.controller,
    required this.onOpenDetail,
  });

  final TimelineActivityGroupController controller;
  final TimelineDetailOpenCallback? onOpenDetail;

  Widget _member(BuildContext context, int index) {
    final visible = controller.visibleMessages;
    final message = visible[index];
    return TimelineActivityMemberView(
      key: ValueKey(message.id),
      message: message,
      pairedTool: message is TimelineSkillGroupMessage
          ? controller.pairedToolFor(message)
          : null,
      onOpenDetail: onOpenDetail,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final count = controller.visibleMessages.length;
      return _activityIndent(
        context,
        Padding(
          key: const ValueKey('timeline-activity-details'),
          padding: EdgeInsets.zero,
          child: count <= 10
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < count; i++) _member(context, i),
                      ],
                    ),
                  ),
                )
              : SizedBox(
                  height: math.min(
                    320,
                    MediaQuery.sizeOf(context).height * .45,
                  ),
                  child: Scrollbar(
                    child: ListView.builder(
                      primary: false,
                      itemCount: count,
                      itemBuilder: _member,
                    ),
                  ),
                ),
        ),
      );
    },
  );
}

class TimelineActivityMemberView extends StatelessWidget {
  const TimelineActivityMemberView({
    required this.message,
    this.pairedTool,
    this.onOpenDetail,
    this.bodyBuilder,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    super.key,
  });

  final Widget Function(String id, String text)? bodyBuilder;
  final TimelineActivityGroupMessage message;
  final TimelineToolGroupMessage? pairedTool;
  final TimelineDetailOpenCallback? onOpenDetail;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  Widget build(BuildContext context) {
    final rolledBack = message.rolledBack;
    final content = Opacity(
      opacity: rolledBack ? 0.52 : 1,
      child: TimelineActivityTileTheme(child: _buildMemberContent(context)),
    );
    return Padding(
      key: StudioDriverKeys.timelineRow(message.id),
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          if (rolledBack)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: DecoratedBox(
                key: StudioDriverKeys.timelineRolledBack(message.id),
                decoration: BoxDecoration(
                  color: context.colors.surfaceContainer,
                  border: Border.all(color: context.colors.outlineVariant),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    context.l10n.timelineRolledBack,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: context.colors.onSurfaceVariant),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMemberContent(BuildContext context) {
    final detailsWidget = timelineActivityMessageDetailNotice(
      context,
      message,
      onOpenDetail: onOpenDetail,
    );
    // 穷尽匹配工作组自有 sealed 类型，绝无组外分支。
    return switch (message) {
      final TimelineThinkingGroupMessage thinking => TimelineReasoningBlock(
        itemId: thinking.id,
        entry: thinking,
        bodyBuilder: bodyBuilder,
        details: detailsWidget,
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
      ),
      final TimelineToolGroupMessage tool => _buildToolContent(
        context,
        tool,
        detailsWidget,
      ),
      final TimelineSkillGroupMessage skill => _TimelineControllerSkillRow(
        skill: skill,
        pairedTool: pairedTool,
        onOpenDetail: onOpenDetail,
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
      ),
    };
  }

  Widget _buildToolContent(
    BuildContext context,
    TimelineToolGroupMessage tool,
    Widget? detailsWidget,
  ) {
    final toolItem = tool;
    final wait = tool.wait;
    if (wait != null) {
      return TimelineWaitPanel(
        presentation: wait,
        identity: tool.id,
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: onExpansionChanged,
        diagnostics: timelineActivityToolDiagnostics(
          item: toolItem,
          details: detailsWidget,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        timelineIsWebSearch(toolItem)
            ? TimelineWebSearchToolCard(
                item: toolItem,
                initiallyExpanded: initiallyExpanded,
                onExpansionChanged: onExpansionChanged,
              )
            : TimelineToolDetails(
                item: toolItem,
                initiallyExpanded: initiallyExpanded,
                onExpansionChanged: onExpansionChanged,
              ),
        ?detailsWidget,
      ],
    );
  }
}

/// 等待面板和独立完成项共享工具诊断、失败原因及截断字段详情入口。
Widget timelineActivityToolDiagnostics({
  required TimelineToolGroupMessage item,
  Widget? details,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    TimelineToolDetails(item: item),
    ?details,
  ],
);

class _TimelineControllerSkillRow extends StatefulWidget {
  const _TimelineControllerSkillRow({
    required this.skill,
    this.pairedTool,
    this.onOpenDetail,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
  });

  final TimelineSkillGroupMessage skill;
  final TimelineToolGroupMessage? pairedTool;
  final TimelineDetailOpenCallback? onOpenDetail;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<_TimelineControllerSkillRow> createState() =>
      _TimelineControllerSkillRowState();
}

class _TimelineControllerSkillRowState
    extends State<_TimelineControllerSkillRow> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final skill = widget.skill;
    final pairedTool = widget.pairedTool;
    final source = skill.source.trim();
    final resourceBase = skill.resourceBase.value.trim();
    final meta = [
      if (source.isNotEmpty) source,
      if (resourceBase.isNotEmpty && resourceBase != source) resourceBase,
    ];
    final toolNotice = pairedTool == null
        ? null
        : timelineActivityMessageDetailNotice(
            context,
            pairedTool,
            onOpenDetail: widget.onOpenDetail,
          );
    final skillNotice = timelineActivityMessageDetailNotice(
      context,
      skill,
      onOpenDetail: widget.onOpenDetail,
    );
    final expandable =
        meta.isNotEmpty || pairedTool != null || skillNotice != null;
    final title = TimelineActivityRow(
      key: StudioDriverKeys.timelineSkillActivation(skill.id),
      icon: Icons.extension_outlined,
      label: switch (skill.cause.kind) {
        SkillActivationCauseKind.tool =>
          context.l10n.timelineSkillAgentActivated(skill.skillName),
        SkillActivationCauseKind.userGesture =>
          context.l10n.timelineSkillUserActivated(skill.skillName),
      },
      expandable: expandable,
      expanded: _expanded,
      tooltip: [
        skill.skillName.trim(),
        ...meta,
      ].where((value) => value.isNotEmpty).join('\n'),
    );
    if (!expandable) return title;
    return ExpansionTile(
      key: ValueKey('timeline-skill-details:${skill.id}'),
      initiallyExpanded: _expanded,
      onExpansionChanged: (expanded) {
        setState(() => _expanded = expanded);
        widget.onExpansionChanged?.call(expanded);
      },
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(
        left: TimelineActivityRow.contentIndent,
        bottom: 8,
      ),
      shape: const Border(),
      collapsedShape: const Border(),
      dense: true,
      minTileHeight: 28,
      showTrailingIcon: false,
      title: title,
      children: [
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              meta.join(' · '),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        if (pairedTool != null)
          TimelineToolDetails(item: pairedTool, inline: true),
        ?toolNotice,
        ?skillNotice,
      ],
    );
  }
}

Widget? timelineActivityMessageDetailNotice(
  BuildContext context,
  TimelineActivityGroupMessage message, {
  required TimelineDetailOpenCallback? onOpenDetail,
}) {
  if (message.details.isNotEmpty) {
    return TimelineDetailNotice(
      itemId: message.id,
      details: [for (final ref in message.details) ref],
      onOpenDetail: onOpenDetail,
    );
  }
  if (message.bodyUnavailable) {
    return TimelineTruncationNotice(itemId: message.id);
  }
  return null;
}

/// 组内思考条目：
/// - 若存在思考概要（`reasoningSummary`），在思考折叠行直接以单行 Markdown 展示最新概要；
/// - 若只有概要（无 `reasoningContent` 且无被截断详情），不提供展开能力（无 `>` 箭头与空展开区）；
/// - 若包含 `reasoningContent` 或被截断详情，点击可展开查看完整思考内容。
class TimelineReasoningBlock extends StatefulWidget {
  const TimelineReasoningBlock({
    required this.itemId,
    required this.entry,
    this.details,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.bodyBuilder,
    super.key,
  });

  final String itemId;
  final Widget Function(String id, String text)? bodyBuilder;
  final TimelineThinkingGroupMessage entry;
  final Widget? details;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<TimelineReasoningBlock> createState() => _TimelineReasoningBlockState();
}

class _TimelineReasoningBlockState extends State<TimelineReasoningBlock> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final summaryChunks = entry.effectiveSummaryChunks
        .map((chunk) => chunk.trim())
        .where((chunk) => chunk.isNotEmpty)
        .toList(growable: false);
    final summary = summaryChunks.join('\n\n');
    final content = [entry.content]
        .where((chunk) => chunk.trim().isNotEmpty)
        .join('\n\n');
    const active = false;
    final isIssue = entry.error != null;
    final latestSummary = summaryChunks.lastOrNull;
    final plainSummary = latestSummary == null
        ? null
        : (plainReasoningSummary(latestSummary) ??
              inlineReasoningSummaryMarkdown(latestSummary));
    final label = plainSummary != null && plainSummary.isNotEmpty
        ? plainSummary
        : timelineReasoningTerminalLabel(
            context,
            entry.error != null
                ? 'failed'
                : entry.cancelled
                ? 'cancelled'
                : 'completed',
            entry.createdAt,
            entry.completedAt,
          );
    final labelWidget = latestSummary == null
        ? null
        : KeyedSubtree(
            key: ValueKey('timeline-thinking-summary-${widget.itemId}'),
            child: _InlineReasoningSummaryMarkdown(
              id: 'timeline-thinking-summary-${widget.itemId}',
              text: latestSummary,
              active: active,
            ),
          );
    // 展开的组内思考消息：如果只有概要（没有正文或截断详情），不做展开能力。
    final expandable =
        content.isNotEmpty || widget.details != null || entry.error != null;
    final title = TimelineActivityRow(
      key: StudioDriverKeys.timelineActivitySummary(widget.itemId),
      icon: Icons.psychology_alt_outlined,
      label: label,
      labelWidget: labelWidget,
      active: active,
      isIssue: isIssue,
      expanded: _expanded,
      expandable: expandable,
    );
    if (!expandable) return title;
    return ExpansionTile(
      initiallyExpanded: _expanded,
      onExpansionChanged: (expanded) {
        setState(() => _expanded = expanded);
        widget.onExpansionChanged?.call(expanded);
      },
      maintainState: false,
      showTrailingIcon: false,
      minTileHeight: 28,
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      title: title,
      children: [
        if (entry.error case final error?)
          Text(error, style: TextStyle(color: context.colors.error)),
        if (content.isNotEmpty)
          Padding(
            key: const ValueKey('timeline-activity-details'),
            padding: const EdgeInsets.only(
              left: TimelineActivityRow.contentIndent,
              top: 2,
              bottom: 4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (summaryChunks.length > 1)
                  _section(
                    context,
                    key: 'timeline-thinking-summary-full-${widget.itemId}',
                    title: context.l10n.timelineReasoningSummary,
                    text: summary,
                  ),
                _section(
                  context,
                  key: 'timeline-thinking-content-${widget.itemId}',
                  title: context.l10n.timelineReasoningContent,
                  text: content,
                ),
              ],
            ),
          ),
        ?widget.details,
      ],
    );
  }

  Widget _section(
    BuildContext context, {
    required String key,
    required String title,
    required String text,
  }) => Padding(
    key: ValueKey(key),
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectionContainer.disabled(
          child: Text(
            title,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),
        widget.bodyBuilder?.call(widget.itemId, text) ??
            TimelineMarkdown(
              id: key,
              text: text,
              onLink: (_) {},
              isSafeLink: (_) => false,
              imageBuilder: (context, url) => Text(url),
            ),
      ],
    ),
  );
}

class _InlineReasoningSummaryMarkdown extends StatelessWidget {
  const _InlineReasoningSummaryMarkdown({
    required this.id,
    required this.text,
    required this.active,
  });

  final String id;
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final textStyle = context.text.bodySmall?.copyWith(
      color: active
          ? context.colors.onSurface
          : context.colors.onSurfaceVariant,
      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
      height: 1.25,
    );
    final inlineText = inlineReasoningSummaryMarkdown(text) ?? text.trim();
    final plainText =
        !timelineNeedsSafeMarkdown(inlineText) &&
        !inlineText.contains('://') &&
        !inlineText.contains('www.');
    if (plainText) {
      return Text(
        inlineText,
        key: ValueKey('plain-$id'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textStyle,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return GptMarkdown(
      inlineText,
      key: ValueKey('gpt-markdown-$id'),
      style: textStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      inlineCodeStyle: InlineCodeStyle(
        fontFamily: studioCodeFontFamily,
        fontSizeFactor: 0.95,
        color: scheme.onSurface,
        backgroundColor: scheme.surfaceContainerLow,
        borderWidth: 0,
        borderRadius: Radius.circular(4),
        padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
      ),
    );
  }
}

/// 终态思考的文案：失败与取消先保留真实状态，其余只报告该条目自身的有效耗时。
String timelineReasoningTerminalLabel(
  BuildContext context,
  String status,
  DateTime? createdAt,
  DateTime? completedAt,
) {
  final l10n = context.l10n;
  return switch (status) {
    'failed' => l10n.timelineReasoningFailed,
    'cancelled' => l10n.timelineReasoningCancelled,
    _ => timelineReasoningElapsedLabel(
      context,
      timelineReasoningElapsed(createdAt, completedAt),
    ),
  };
}

/// 耗时只来自同一思考条目的创建时间与 canonical 终态时间。
Duration? timelineReasoningElapsed(DateTime? createdAt, DateTime? completedAt) {
  if (createdAt == null || completedAt == null) return null;
  final elapsed = completedAt.difference(createdAt);
  return elapsed.isNegative ? null : elapsed;
}

String timelineReasoningElapsedLabel(BuildContext context, Duration? elapsed) {
  final l10n = context.l10n;
  if (elapsed == null) return l10n.timelineReasoningEnded;
  final seconds = elapsed.inSeconds;
  if (seconds <= 0) return l10n.timelineReasoningElapsedUnderSecond;
  if (seconds < 60) return l10n.timelineReasoningElapsedSeconds(seconds);
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return remainder == 0
      ? l10n.timelineReasoningElapsedMinutes(minutes)
      : l10n.timelineReasoningElapsedMinutesSeconds(minutes, remainder);
}

class TimelineDetailNotice extends StatelessWidget {
  const TimelineDetailNotice({
    required this.itemId,
    required this.details,
    this.onOpenDetail,
    super.key,
  });

  final String itemId;
  final List<TimelineActivityDetailRef> details;
  final TimelineDetailOpenCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    void open(ThreadContentFieldView field) =>
        onOpenDetail?.call(itemId, field);
    return SelectionContainer.disabled(
      child: Padding(
        key: StudioDriverKeys.timelineItemBodyNotice(itemId),
        padding: const EdgeInsets.only(top: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final detail in details)
              Semantics(
                container: true,
                button: true,
                label: _activityFieldLabel(context, detail.field),
                hint: context.l10n.timelineItemBodyLoad,
                onTap: () => open(detail.field),
                excludeSemantics: true,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: StudioDriverKeys.timelineDetailOpen(
                      itemId,
                      StudioDriverKeyValues.timelineDetailField(detail.field),
                    ),
                    onTap: () => open(detail.field),
                    canRequestFocus: true,
                    excludeFromSemantics: true,
                    child: TimelineActivityRow(
                      icon: _activityFieldIcon(detail.field),
                      label: _activityFieldLabel(context, detail.field),
                      expandable: true,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TimelineTruncationNotice extends StatelessWidget {
  const TimelineTruncationNotice({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Padding(
        key: StudioDriverKeys.timelineItemBodyNotice(itemId),
        padding: const EdgeInsets.only(top: 6),
        child: TimelineActivityRow(
          icon: Icons.info_outline,
          label: context.l10n.timelineItemBodyUnavailable,
          expandable: false,
        ),
      ),
    );
  }
}

String _activityFieldLabel(
  BuildContext context,
  ThreadContentFieldView field,
) => switch (field) {
  ThreadToolArgumentsFieldView() => context.l10n.timelineToolArguments,
  ThreadToolResultFieldView() => context.l10n.timelineToolOutput,
  ThreadToolOutputArtifactsFieldView() => context.l10n.timelineToolOutput,
  ThreadRawPayloadFieldView() => context.l10n.timelineRawRecord,
  ThreadThinkingSummaryFieldView() => context.l10n.timelineReasoningSummary,
  ThreadThinkingContentFieldView() => context.l10n.timelineReasoningContent,
  ThreadToolUserInputFieldView() => context.l10n.timelineUserInputYourAnswer,
  ThreadTextFieldView() => context.l10n.timelineItemBodyLoad,
};

IconData _activityFieldIcon(ThreadContentFieldView field) => switch (field) {
  ThreadToolArgumentsFieldView() => Icons.tune,
  ThreadToolResultFieldView() ||
  ThreadToolOutputArtifactsFieldView() => Icons.terminal,
  ThreadRawPayloadFieldView() => Icons.history,
  ThreadThinkingSummaryFieldView() => Icons.summarize_outlined,
  ThreadThinkingContentFieldView() => Icons.subject,
  ThreadToolUserInputFieldView() => Icons.chat_bubble_outline,
  ThreadTextFieldView() => Icons.unfold_more,
};

String groupWorkedLabel(BuildContext context, Duration elapsed) {
  final l10n = context.l10n;
  final seconds = elapsed.inSeconds;
  if (seconds <= 0) return l10n.timelineGroupWorkedUnderSecond;
  if (seconds < 60) return l10n.timelineGroupWorkedSeconds(seconds);
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return remainder == 0
      ? l10n.timelineGroupWorkedMinutes(minutes)
      : l10n.timelineGroupWorkedMinutesSeconds(minutes, remainder);
}

Widget _activityIndent(BuildContext context, Widget child) => Container(
  margin: const EdgeInsetsDirectional.only(
    start: TimelineActivityRow.groupIndent,
  ),
  padding: const EdgeInsetsDirectional.only(start: 12),
  decoration: BoxDecoration(
    border: BorderDirectional(
      start: BorderSide(color: context.colors.outlineVariant),
    ),
  ),
  child: child,
);
