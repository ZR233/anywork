import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:anywork_client/studio_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../app/theme/studio_tokens.dart';
import '../../domain/models/studio_models.dart';
import '../../l10n/studio_l10n.dart';
import '../../platform/external_url_launcher.dart';
import '../../shared/studio_chrome.dart';
import '../../shared/studio_driver_key_values.dart';
import '../../shared/studio_driver_keys.dart';
import '../../shared/typed_json.dart';
import 'markdown_repair.dart';
import 'timeline_activity_group_models.dart';
import 'timeline_activity_row.dart';
import 'timeline_wait_blocks.dart';

export 'timeline_activity_group_models.dart';

part 'timeline_agent_blocks.dart';
part 'timeline_markdown_blocks.dart';
part 'timeline_remote_image_blocks.dart';
part 'timeline_tool_blocks.dart';

typedef TimelineRemoteImageProviderFactory = ImageProvider Function(String url);

final timelineRemoteImageProviderFactoryProvider =
    Provider<TimelineRemoteImageProviderFactory>((ref) => NetworkImage.new);

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
    final worked = _groupWorkedLabel(context, elapsed);
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
    return _TimelineControllerMemberBlock(
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
      return timelineActivityIndent(
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

class _TimelineControllerMemberBlock extends StatelessWidget {
  const _TimelineControllerMemberBlock({
    required this.message,
    this.pairedTool,
    this.onOpenDetail,
    super.key,
  });

  final TimelineActivityGroupMessage message;
  final TimelineToolGroupMessage? pairedTool;
  final TimelineDetailOpenCallback? onOpenDetail;

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
        entry: timelineEntryFromThinkingGroupMessage(thinking),
        details: detailsWidget,
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
      ),
    };
  }

  Widget _buildToolContent(
    BuildContext context,
    TimelineToolGroupMessage tool,
    Widget? detailsWidget,
  ) {
    final toolItem = TimelineToolItem(timelineEntryFromToolGroupMessage(tool));
    final wait = tool.wait;
    if (wait != null) {
      return TimelineWaitPanel(
        presentation: wait,
        identity: tool.id,
        diagnostics: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TimelineToolDetails(item: toolItem),
            ?detailsWidget,
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        timelineIsWebSearch(toolItem)
            ? TimelineWebSearchToolCard(item: toolItem)
            : TimelineToolDetails(item: toolItem),
        ?detailsWidget,
      ],
    );
  }
}

class _TimelineControllerSkillRow extends StatefulWidget {
  const _TimelineControllerSkillRow({
    required this.skill,
    this.pairedTool,
    this.onOpenDetail,
  });

  final TimelineSkillGroupMessage skill;
  final TimelineToolGroupMessage? pairedTool;
  final TimelineDetailOpenCallback? onOpenDetail;

  @override
  State<_TimelineControllerSkillRow> createState() =>
      _TimelineControllerSkillRowState();
}

class _TimelineControllerSkillRowState
    extends State<_TimelineControllerSkillRow> {
  bool _expanded = false;

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
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
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
          TimelineToolDetails(
            item: TimelineToolItem(
              timelineEntryFromToolGroupMessage(pairedTool),
            ),
            inline: true,
          ),
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
      details: [
        for (final ref in message.details)
          StudioTimelineDetailRef(
            field: ref.field,
            revision: 1,
            totalBytes: 1,
            previewBytes: 0,
          ),
      ],
      onOpenDetail: onOpenDetail,
    );
  }
  if (message.bodyUnavailable) {
    return TimelineTruncationNotice(itemId: message.id);
  }
  return null;
}

TimelineEntry timelineEntryFromThinkingGroupMessage(
  TimelineThinkingGroupMessage thinking,
) => TimelineEntry(
  id: thinking.id,
  groupId: '',
  threadId: '',
  turnId: '',
  type: TimelineEntryType.reasoning,
  order: thinking.order,
  sequence: thinking.order,
  revision: 1,
  createdAt: thinking.createdAt,
  updatedAt: thinking.completedAt,
  completedAt: thinking.completedAt,
  text: '',
  reasoningSummary: thinking.effectiveSummaryChunks,
  reasoningContent: thinking.hasContent ? [thinking.content] : const [],
  status: 'completed',
  contextDisposition: thinking.rolledBack
      ? ThreadContextDisposition.rolledBack
      : ThreadContextDisposition.active,
);

TimelineEntry timelineEntryFromToolGroupMessage(
  TimelineToolGroupMessage tool,
) => TimelineEntry(
  id: tool.id,
  groupId: '',
  threadId: '',
  turnId: '',
  type: TimelineEntryType.tool,
  order: tool.order,
  sequence: tool.order,
  revision: 1,
  createdAt: tool.createdAt,
  updatedAt: tool.completedAt,
  completedAt: tool.completedAt,
  error: tool.error,
  text: '',
  status: tool.statusString,
  tool: TimelineToolPart(
    toolCallId: tool.toolCallId,
    callId: tool.toolCallId,
    name: tool.name,
    arguments: tool.arguments,
    result: tool.output,
    outputArtifacts: tool.outputArtifacts,
    attachments: const [],
    wait: tool.wait,
    timedOut: false,
  ),
  contextDisposition: tool.rolledBack
      ? ThreadContextDisposition.rolledBack
      : ThreadContextDisposition.active,
);

/// 实时时间线展示租约（[TimelineDisplayLease]）使用的活动组块。
class TimelineLiveActivityGroupBlock extends StatefulWidget {
  const TimelineLiveActivityGroupBlock({
    required this.group,
    this.onOpenDetail,
    super.key,
  });

  final TimelineActivityGroup group;
  final TimelineDetailOpenCallback? onOpenDetail;

  @override
  State<TimelineLiveActivityGroupBlock> createState() =>
      _TimelineLiveActivityGroupBlockState();
}

class _TimelineLiveActivityGroupBlockState
    extends State<TimelineLiveActivityGroupBlock> {
  final ExpansibleController _expansion = ExpansibleController();

  @override
  void initState() {
    super.initState();
    widget.group.addListener(_onGroupChanged);
  }

  void _onGroupChanged() {
    if (widget.group.expanded && !_expansion.isExpanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.group.expanded && !_expansion.isExpanded) {
          _expansion.expand();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant TimelineLiveActivityGroupBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.group, widget.group)) {
      oldWidget.group.removeListener(_onGroupChanged);
      widget.group.addListener(_onGroupChanged);
      _onGroupChanged();
    }
  }

  @override
  void dispose() {
    widget.group.removeListener(_onGroupChanged);
    _expansion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return ListenableBuilder(
      listenable: group,
      builder: (context, body) {
        if (group.length == 0) return const SizedBox.shrink();
        return Padding(
          key: StudioDriverKeys.timelineRow(group.id),
          padding: const EdgeInsets.only(bottom: 6),
          child: TimelineActivityTileTheme(
            child: ExpansionTile(
              controller: _expansion,
              initiallyExpanded: group.expanded,
              onExpansionChanged: group.setExpanded,
              maintainState: false,
              showTrailingIcon: false,
              minTileHeight: 28,
              dense: true,
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 2),
              shape: const Border(),
              collapsedShape: const Border(),
              title: TimelineActivityRow(
                key: StudioDriverKeys.timelineActivitySummary(group.id),
                label: timelineActivityGroupLabel(context, group),
                active: group.activeCount > 0,
                expanded: group.expanded,
                expandable: timelineGroupExpandable(group),
              ),
              children: [body!],
            ),
          ),
        );
      },
      child: _TimelineActivityGroupContents(
        group: group,
        onOpenDetail: widget.onOpenDetail,
      ),
    );
  }
}

/// 单成员纯思考组在概要、完整内容与截断详情均为空时不承诺一个空的展开区。
bool timelineGroupExpandable(TimelinePresentationItem item) {
  if (item.kind != TimelinePresentationKind.activity ||
      item.thinkingCount != 1 ||
      item.toolCount != 0 ||
      item.skillCount != 0 ||
      item.length != 1) {
    return true;
  }
  final payload = item.first;
  final state = payload.item.state;
  if (state is! ThreadThinkingItemStateView) return true;
  return state.summary.any((chunk) => chunk.trim().isNotEmpty) ||
      state.content.any((chunk) => chunk.trim().isNotEmpty) ||
      payload.details.any((detail) => detail.truncated) ||
      payload.hasOmittedBody;
}

/// 思考与工具活动组顶层折叠行的汇总文案：工作时长 + 工具/技能调用数量。
String timelineActivityGroupLabel(
  BuildContext context,
  TimelinePresentationItem item,
) {
  final counts = [
    if (item.toolCount > 0) timelineToolCountPhrase(context, item),
    if (item.skillCount > 0) context.l10n.statusSkillsCount(item.skillCount),
  ];
  final onlySkills =
      item.toolCount == 0 && item.thinkingCount == 0 && counts.isNotEmpty;
  // 纯技能组直接说明技能数量，既不显示“0 个工具”，也不虚构思考时长。
  if (onlySkills) return counts.join(' · ');

  final elapsed = item is TimelineActivityGroup ? item.elapsedDuration : null;
  if (item.thinkingCount > 0 && item.toolCount == 0 && item.skillCount == 0) {
    final hasFailureOrCancellation = item.payloads.any(
      (payload) =>
          payload.item.state is ThreadThinkingItemStateView &&
          (payload.item.status == 'failed' ||
              payload.item.status == 'cancelled'),
    );
    if (item.activeCount == 0 && !hasFailureOrCancellation && elapsed != null) {
      return _groupWorkedLabel(context, elapsed);
    }
    return timelineReasoningGroupLabel(context, item);
  }

  if (item.activeCount == 0 && elapsed != null) {
    final worked = _groupWorkedLabel(context, elapsed);
    return counts.isEmpty ? worked : '$worked · ${counts.join(' · ')}';
  }

  final title = item.thinkingCount == 0
      ? context.l10n.timelineToolGroupTitle
      : item.toolCount > 0 || item.skillCount > 0
      ? context.l10n.timelineActivityTitle
      : context.l10n.timelineReasoningFallback;
  if (counts.isEmpty) return title;
  return '$title · ${counts.join(' · ')}';
}

String _groupWorkedLabel(BuildContext context, Duration elapsed) {
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

/// 工具侧的计数文案：运行中与需要注意仍是同一段短语的一部分。
String timelineToolCountPhrase(
  BuildContext context,
  TimelinePresentationItem item,
) {
  return switch ((item.issueCount > 0, item.runningToolCount > 0)) {
    (true, true) => context.l10n.timelineToolGroupSummaryRunningWithIssues(
      item.toolCount,
      item.runningToolCount,
      item.issueCount,
    ),
    (true, false) => context.l10n.timelineToolGroupSummaryIssues(
      item.toolCount,
      item.issueCount,
    ),
    (false, true) => context.l10n.timelineToolGroupSummaryRunning(
      item.toolCount,
      item.runningToolCount,
    ),
    (false, false) => context.l10n.timelineToolGroupSummary(item.toolCount),
  };
}

/// 纯思考组的回退摘要：成员未完成、失败、取消或缺失时间时使用。
String timelineReasoningGroupLabel(
  BuildContext context,
  TimelinePresentationItem item,
) {
  final l10n = context.l10n;
  var total = Duration.zero;
  var active = false;
  var failed = false;
  var cancelled = false;
  var unknown = false;
  for (final payload in item.payloads) {
    final member = payload.item;
    if (member.state is! ThreadThinkingItemStateView) continue;
    active = active || !member.isTerminal;
    failed = failed || member.status == 'failed';
    if (member.status == 'cancelled') cancelled = true;
    final elapsed = timelineReasoningElapsed(
      member.createdAt,
      member.completedAt,
    );
    if (elapsed == null) {
      unknown = true;
    } else {
      total += elapsed;
    }
  }
  if (active) return l10n.timelineReasoningActive;
  if (failed) return l10n.timelineReasoningFailed;
  if (cancelled) return l10n.timelineReasoningCancelled;
  if (unknown) return l10n.timelineReasoningEnded;
  return timelineReasoningElapsedLabel(context, total);
}

class _TimelineActivityGroupContents extends StatelessWidget {
  const _TimelineActivityGroupContents({
    required this.group,
    required this.onOpenDetail,
  });

  final TimelineActivityGroup group;
  final TimelineDetailOpenCallback? onOpenDetail;

  Widget _member(BuildContext context, int index) {
    final id = group.visibleMemberIds[index];
    final paired = group.pairedToolId(id);
    if (group.payload(id)?.item.skill != null) {
      return TimelineSkillActivity(
        key: ValueKey('timeline-skill-activity-$id'),
        skill: group.member(id),
        tool: paired == null ? null : group.member(paired),
        onOpenDetail: onOpenDetail,
      );
    }
    return ValueListenableBuilder<TimelineMessagePayload>(
      key: ValueKey(id),
      valueListenable: group.member(id),
      builder: (context, payload, _) => _TimelineActivityMemberBlock(
        payload: payload,
        onOpenDetail: onOpenDetail,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: group.structure,
    builder: (context, _, child) => timelineActivityIndent(
      context,
      Padding(
        key: const ValueKey('timeline-activity-details'),
        padding: EdgeInsets.zero,
        child: group.visibleMemberIds.length <= 10
            ? ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  primary: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < group.visibleMemberIds.length; i++)
                        _member(context, i),
                    ],
                  ),
                ),
              )
            : SizedBox(
                height: math.min(320, MediaQuery.sizeOf(context).height * .45),
                child: Scrollbar(
                  child: ListView.builder(
                    primary: false,
                    itemCount: group.visibleMemberIds.length,
                    itemBuilder: _member,
                  ),
                ),
              ),
      ),
    ),
  );
}

/// 活动组成员整体缩进一档，并在左侧画低对比引导线表示归属。
Widget timelineActivityIndent(BuildContext context, Widget child) {
  const half = TimelineActivityRow.groupIndent / 2;
  return Padding(
    padding: const EdgeInsets.only(left: half),
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: context.colors.outlineVariant.withValues(alpha: 0.55),
            width: 1,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: half),
        child: child,
      ),
    ),
  );
}

class _TimelineActivityMemberBlock extends StatelessWidget {
  const _TimelineActivityMemberBlock({
    required this.payload,
    this.pairedSkillTool,
    this.onOpenDetail,
  });

  final TimelineMessagePayload payload;
  final TimelineMessagePayload? pairedSkillTool;
  final TimelineDetailOpenCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final item = payload.item;
    if (timelineRendersNoContent(item)) return const SizedBox.shrink();
    final rolledBack =
        item.contextDisposition == ThreadContextDisposition.rolledBack;
    Widget content = Opacity(
      opacity: rolledBack ? 0.52 : 1,
      child: TimelineActivityTileTheme(child: _memberContent(context)),
    );
    return Padding(
      key: StudioDriverKeys.timelineRow(item.id),
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          if (rolledBack)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: DecoratedBox(
                key: StudioDriverKeys.timelineRolledBack(item.id),
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

  Widget _memberContent(BuildContext context) {
    final item = payload.item;
    return switch (item.state) {
      ThreadThinkingItemStateView() => TimelineReasoningBlock(
        itemId: item.id,
        entry: timelineEntryViewOf(item),
        details: timelinePayloadDetailNotice(
          context,
          payload,
          onOpenDetail: onOpenDetail,
        ),
      ),
      ThreadToolItemStateView() => _toolContent(context, item),
      final ThreadAgentItemStateView agent => TimelineAgentPart(agent: agent),
      ThreadSkillItemStateView() => TimelineSkillActivityRow(
        payload: payload,
        tool: pairedSkillTool,
        onOpenDetail: onOpenDetail,
      ),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _toolContent(BuildContext context, ThreadItemView item) {
    final wait = item.tool?.wait;
    if (wait != null) {
      final toolItem = TimelineToolItem(timelineEntryViewOf(item));
      return TimelineWaitPanel(
        presentation: wait,
        identity: item.id,
        diagnostics: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TimelineToolDetails(item: toolItem),
            ?timelinePayloadDetailNotice(
              context,
              payload,
              onOpenDetail: onOpenDetail,
            ),
          ],
        ),
      );
    }
    final toolItem = TimelineToolItem(timelineEntryViewOf(item));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        timelineIsWebSearch(toolItem)
            ? TimelineWebSearchToolCard(item: toolItem)
            : TimelineToolDetails(item: toolItem),
        ?timelinePayloadDetailNotice(
          context,
          payload,
          onOpenDetail: onOpenDetail,
        ),
      ],
    );
  }
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
    super.key,
  });

  final String itemId;
  final TimelineEntry entry;
  final Widget? details;

  @override
  State<TimelineReasoningBlock> createState() => _TimelineReasoningBlockState();
}

class _TimelineReasoningBlockState extends State<TimelineReasoningBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final summaryChunks = entry.reasoningSummary
        .map((chunk) => chunk.trim())
        .where((chunk) => chunk.isNotEmpty)
        .toList(growable: false);
    final summary = summaryChunks.join('\n\n');
    final content = entry.reasoningContent
        .where((chunk) => chunk.trim().isNotEmpty)
        .join('\n\n');
    final active = !isTerminalTimelineStatus(entry.status);
    final isIssue = timelineIssueStatuses.contains(entry.status);
    final latestSummary = summaryChunks.lastOrNull;
    final plainSummary = latestSummary == null
        ? null
        : (plainReasoningSummary(latestSummary) ??
              inlineReasoningSummaryMarkdown(latestSummary));
    final label = plainSummary != null && plainSummary.isNotEmpty
        ? plainSummary
        : active
        ? context.l10n.timelineReasoningActive
        : timelineReasoningTerminalLabel(
            context,
            entry.status,
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
    final expandable = content.isNotEmpty || widget.details != null;
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
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
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
        TimelineAgentMarkdown(
          id: key,
          text: text,
          surface: TimelineMarkdownSurface.reasoning,
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
        !_streamingMarkdownSyntax.hasMatch(inlineText) &&
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
      repairAgentMarkdownForDisplay(inlineText),
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

/// 一条技能激活的可见活动行，必要时与原 `skill_view` 调用共享这一行。
class TimelineSkillActivityRow extends StatefulWidget {
  const TimelineSkillActivityRow({
    required this.payload,
    this.tool,
    this.onOpenDetail,
    super.key,
  });

  final TimelineMessagePayload payload;
  final TimelineMessagePayload? tool;
  final TimelineDetailOpenCallback? onOpenDetail;

  @override
  State<TimelineSkillActivityRow> createState() =>
      _TimelineSkillActivityRowState();
}

class _TimelineSkillActivityRowState extends State<TimelineSkillActivityRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final activation = timelineSkillOf(widget.payload.item);
    if (activation == null) return const SizedBox.shrink();
    final tool = widget.tool;
    final meta = _skillActivityMeta(activation);
    final toolNotice = tool == null
        ? null
        : timelinePayloadDetailNotice(
            context,
            tool,
            onOpenDetail: widget.onOpenDetail,
          );
    final skillNotice = timelinePayloadDetailNotice(
      context,
      widget.payload,
      onOpenDetail: widget.onOpenDetail,
    );
    final expandable = meta.isNotEmpty || tool != null || skillNotice != null;
    final title = TimelineActivityRow(
      key: StudioDriverKeys.timelineSkillActivation(widget.payload.item.id),
      icon: Icons.extension_outlined,
      label: switch (activation.cause.kind) {
        SkillActivationCauseKind.tool =>
          context.l10n.timelineSkillAgentActivated(activation.name),
        SkillActivationCauseKind.userGesture =>
          context.l10n.timelineSkillUserActivated(activation.name),
      },
      active: !widget.payload.item.isTerminal,
      isIssue: timelineIssueStatuses.contains(widget.payload.item.status),
      expandable: expandable,
      expanded: _expanded,
      tooltip: [
        activation.name.trim(),
        ...meta,
      ].where((value) => value.isNotEmpty).join('\n'),
    );
    if (!expandable) return title;
    return ExpansionTile(
      key: ValueKey('timeline-skill-details:${widget.payload.item.id}'),
      initiallyExpanded: _expanded,
      onExpansionChanged: (expanded) => setState(() => _expanded = expanded),
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
        if (tool != null)
          TimelineToolDetails(
            item: TimelineToolItem(timelineEntryViewOf(tool.item)),
            inline: true,
          ),
        ?toolNotice,
        ?skillNotice,
      ],
    );
  }
}

List<String> _skillActivityMeta(TimelineSkillActivation activation) {
  final source = activation.source.trim();
  final resourceBase = activation.resourceBase.value.trim();
  return [
    if (source.isNotEmpty) source,
    if (resourceBase.isNotEmpty && resourceBase != source) resourceBase,
  ];
}

class TimelineSkillActivity extends StatelessWidget {
  const TimelineSkillActivity({
    required this.skill,
    this.tool,
    this.onOpenDetail,
    super.key,
  });

  final ValueListenable<TimelineMessagePayload> skill;
  final ValueListenable<TimelineMessagePayload>? tool;
  final TimelineDetailOpenCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final tool = this.tool;
    if (tool == null) {
      return ValueListenableBuilder<TimelineMessagePayload>(
        valueListenable: skill,
        builder: (context, payload, _) => _TimelineActivityMemberBlock(
          payload: payload,
          onOpenDetail: onOpenDetail,
        ),
      );
    }
    return ValueListenableBuilder<TimelineMessagePayload>(
      valueListenable: skill,
      builder: (context, skillPayload, _) =>
          ValueListenableBuilder<TimelineMessagePayload>(
            valueListenable: tool,
            builder: (context, toolPayload, _) => _TimelineActivityMemberBlock(
              payload: skillPayload,
              pairedSkillTool: toolPayload,
              onOpenDetail: onOpenDetail,
            ),
          ),
    );
  }
}

/// 一条成员预览的详情入口：技能行复用同一入口访问原调用与被省略的正文。
Widget? timelinePayloadDetailNotice(
  BuildContext context,
  TimelineMessagePayload payload, {
  TimelineDetailOpenCallback? onOpenDetail,
}) {
  final truncated = [
    for (final detail in payload.details)
      if (detail.truncated) detail,
  ];
  if (truncated.isEmpty) {
    if (!payload.hasOmittedBody) return null;
    return TimelineTruncationNotice(itemId: payload.item.id);
  }
  return TimelineDetailNotice(
    itemId: payload.item.id,
    details: truncated,
    onOpenDetail: onOpenDetail,
  );
}

class TimelineDetailNotice extends StatelessWidget {
  const TimelineDetailNotice({
    required this.itemId,
    required this.details,
    this.onOpenDetail,
    super.key,
  });

  final String itemId;
  final List<StudioTimelineDetailRef> details;
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
                label: timelineFieldLabel(context, detail.field),
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
                      icon: timelineFieldIcon(detail.field),
                      label: timelineFieldLabel(context, detail.field),
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

String timelineFieldLabel(BuildContext context, ThreadContentFieldView field) =>
    switch (field) {
      ThreadToolArgumentsFieldView() => context.l10n.timelineToolArguments,
      ThreadToolResultFieldView() => context.l10n.timelineToolOutput,
      ThreadToolOutputArtifactsFieldView() => context.l10n.timelineToolOutput,
      ThreadRawPayloadFieldView() => context.l10n.timelineRawRecord,
      ThreadThinkingSummaryFieldView() => context.l10n.timelineReasoningSummary,
      ThreadThinkingContentFieldView() => context.l10n.timelineReasoningContent,
      ThreadToolUserInputFieldView() =>
        context.l10n.timelineUserInputYourAnswer,
      ThreadTextFieldView() => context.l10n.timelineItemBodyLoad,
    };

IconData timelineFieldIcon(ThreadContentFieldView field) => switch (field) {
  ThreadToolArgumentsFieldView() => Icons.tune,
  ThreadToolResultFieldView() ||
  ThreadToolOutputArtifactsFieldView() => Icons.terminal,
  ThreadRawPayloadFieldView() => Icons.history,
  ThreadThinkingSummaryFieldView() => Icons.summarize_outlined,
  ThreadThinkingContentFieldView() => Icons.subject,
  ThreadToolUserInputFieldView() => Icons.chat_bubble_outline,
  ThreadTextFieldView() => Icons.unfold_more,
};

bool timelineRendersNoContent(ThreadItemView item) => switch (item.kind) {
  ThreadItemKind.inference || ThreadItemKind.file => true,
  ThreadItemKind.turn =>
    !item.isTerminal || (item.error == null || item.error!.isEmpty),
  _ => false,
};

bool timelineIsCompactActivity(ThreadItemView item) => switch (item.kind) {
  ThreadItemKind.reasoning ||
  ThreadItemKind.toolCall ||
  ThreadItemKind.contextCompaction ||
  ThreadItemKind.skill ||
  ThreadItemKind.agent => true,
  _ => false,
};

TimelineEntry timelineEntryViewOf(ThreadItemView item) => TimelineEntry(
  id: item.id,
  groupId: item.turnId,
  threadId: item.threadId,
  turnId: item.turnId,
  type: switch (item.kind) {
    ThreadItemKind.userMessage ||
    ThreadItemKind.parentAgentMessage ||
    ThreadItemKind.agentMessage ||
    ThreadItemKind.raw ||
    ThreadItemKind.agent => TimelineEntryType.text,
    ThreadItemKind.reasoning => TimelineEntryType.reasoning,
    ThreadItemKind.skill => TimelineEntryType.skill,
    ThreadItemKind.toolCall => TimelineEntryType.tool,
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
  text: item.kind == ThreadItemKind.reasoning ? '' : item.text,
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
  skill: timelineSkillOf(item),
  attachments: item.attachments,
  contextDisposition: item.contextDisposition,
);

TimelineSkillActivation? timelineSkillOf(ThreadItemView item) {
  final skill = item.skill;
  if (skill == null) return null;
  return TimelineSkillActivation(
    name: skill.name,
    source: skill.source,
    providerId: skill.providerId,
    resourceBase: skill.resourceBase,
    cause: skill.cause,
    activatedAt: skill.activatedAt,
  );
}

String timelineFormatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String timelineAttachmentDescription(
  BuildContext context,
  ThreadAttachmentView attachment,
) {
  final dimensions = attachment.width != null && attachment.height != null
      ? ' · ${attachment.width}×${attachment.height}'
      : '';
  final label = attachment.filename ?? context.l10n.attachmentFallback;
  return '$label$dimensions · ${timelineFormatBytes(attachment.byteSize)}';
}

class TimelineMetaRow extends StatelessWidget {
  const TimelineMetaRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Icon(icon, size: 17, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(
                    color: context.colors.onSurface,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showStudioImageDialog(
  BuildContext context,
  ImageProvider image, {
  required Key dialogKey,
  String? label,
  String? sourcePath,
  void Function(BuildContext)? onShowDetails,
  Key? detailsKey,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      key: dialogKey,
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: math.min(
          1000,
          math.max(240, MediaQuery.sizeOf(context).width - 80),
        ),
        height: math.min(
          760,
          math.max(200, MediaQuery.sizeOf(context).height - 80),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 5,
                      child: Center(
                        child: Image(
                          image: image,
                          errorBuilder: (context, error, stackTrace) => Center(
                            child: Text(context.l10n.timelineImageLoadFailed),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filledTonal(
                      key: StudioDriverKeys.timelineImageClose,
                      tooltip: context.l10n.timelineImageClose,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
            if ((label?.isNotEmpty ?? false) ||
                (sourcePath?.isNotEmpty ?? false) ||
                onShowDetails != null)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: context.colors.outlineVariant),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectionArea(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (label?.isNotEmpty == true)
                              Text(label!, style: context.text.titleSmall),
                            if (sourcePath?.isNotEmpty == true &&
                                sourcePath != label)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: label?.isNotEmpty == true ? 4 : 0,
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 96,
                                  ),
                                  child: SingleChildScrollView(
                                    child: Text(
                                      sourcePath!,
                                      style: context.text.bodySmall?.copyWith(
                                        color: context.colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (onShowDetails != null)
                      IconButton(
                        key: detailsKey,
                        tooltip: context.l10n.timelineToolOutput,
                        onPressed: () => onShowDetails(context),
                        icon: const Icon(Icons.info_outline),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
