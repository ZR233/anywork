import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:anywork_client/models.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../state/tool_presentation.dart';
import '../state/tool_display.dart';
import '../state/tool_display_registry.dart';
import '../state/timeline_display_unit.dart';
import 'timeline_activity_row.dart';
import 'timeline_content_range_view.dart' show TimelineBodyReadQualification;
import 'timeline_activity_clock.dart';
import 'timeline_lsp_tool_view.dart';
import 'timeline_patch_diff_view.dart';
import 'timeline_tool_detail_panel.dart';

/// 内联正文和声明窗口都经过同一登记，不直接公开参数信封。
Widget? timelineToolInlineBody(
  BuildContext context,
  TimelineToolPresentation item, {
  TimelineLspMarkdownBuilder? markdownBuilder,
  ToolAcceptanceProjection? acceptance,
}) {
  final spec = toolDisplayRegistry[item.presentationContract];
  if (spec == null) return Text(context.l10n.timelineToolUnknownFormat);
  if (spec.isLsp) {
    return timelineLspInlineBody(item, markdownBuilder: markdownBuilder);
  }
  final inputValues = spec.decodeInput(context.l10n, item.arguments);
  final outputValues = spec.readsOutput(item.statusString, output: item.output)
      ? acceptance != null && acceptance.state != ToolAcceptance.pending
            ? spec.acceptanceDetails(context.l10n, acceptance)
            : spec.decodeOutput(context.l10n, item.output)
      : const <ToolDetailValue>[];
  if (inputValues.isEmpty &&
      outputValues.isEmpty &&
      spec.inputBody != ToolInputBody.patch) {
    return null;
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (spec.inputBody == ToolInputBody.patch)
        ?timelineApplyPatchBody(item.arguments)
      else if (inputValues.isNotEmpty)
        TimelineToolSemanticBody(values: inputValues),
      if (outputValues.isNotEmpty)
        TimelineToolSemanticBody(values: outputValues),
    ],
  );
}

Widget timelineToolWindowBody(
  BuildContext context,
  TimelineToolPresentation item,
  String text, {
  required bool input,
  TimelineLspMarkdownBuilder? markdownBuilder,
  ToolAcceptanceProjection? acceptance,
}) {
  final spec = toolDisplayRegistry[item.presentationContract];
  if (spec == null) return Text(context.l10n.timelineToolUnknownFormat);
  if (input && spec.inputBody == ToolInputBody.patch) {
    return timelineApplyPatchWindowBody(text);
  }
  if (!input && spec.isLsp) {
    return timelineLspWindowBody(item, text, markdownBuilder: markdownBuilder);
  }
  if (!input && spec.requiresAcceptance) {
    return TimelineToolSemanticBody(
      values: spec.acceptanceDetails(
        context.l10n,
        acceptance ?? const ToolAcceptanceProjection(ToolAcceptance.pending),
      ),
    );
  }
  if (!input &&
      spec.outputFormat == ToolOutputFormat.structured &&
      text.trim().isEmpty) {
    return TimelineToolSemanticBody(
      values: [
        ToolDetailUnavailable(context.l10n.timelineToolStructuredUnavailable),
      ],
    );
  }
  return TimelineToolSemanticBody(
    values: input
        ? spec.decodeInput(context.l10n, text)
        : spec.decodeOutput(context.l10n, text),
  );
}

/// 所有工具共用同一轻量活动行：语义图标、单行状态文案与紧邻文案的箭头。
///
/// 参数、结果、错误、退出码、拒绝原因与附件诊断按需展开，完整字段仍由详情查看器
/// 读取；成功 workflow mutation 的内部 snapshot 继续隐藏（design/19 §19.9）。
class TimelineToolDetails extends StatefulWidget {
  const TimelineToolDetails({
    required this.item,
    this.inline = false,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    this.declaredContentBuilder,
    this.declaredContentIdentity,
    this.additionalContentBuilder,
    this.markdownBuilder,
    super.key,
  }) : assert(
         declaredContentBuilder == null || declaredContentIdentity != null,
       );

  final TimelineToolPresentation item;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final List<Widget> Function(
    ValueChanged<ContentWindow> onOutputRead,
    ToolAcceptanceProjection? acceptance,
  )?
  declaredContentBuilder;
  final Object? declaredContentIdentity;
  final WidgetBuilder? additionalContentBuilder;
  final TimelineLspMarkdownBuilder? markdownBuilder;

  /// 外层已经提供折叠身份（例如接管该行可见性的技能行）时只渲染详情主体，
  /// 不再重复一行工具标题；参数、结果、诊断与错误仍来自同一实现。
  final bool inline;

  @override
  State<TimelineToolDetails> createState() => _TimelineToolDetailsState();
}

class _TimelineToolDetailsState extends State<TimelineToolDetails> {
  ToolAcceptanceProjection? _windowAcceptance;
  Object _callbackEpoch = Object();
  TimelineExpansionIntent? _group;
  Object? _groupGeneration;

  ToolAcceptanceProjection? get _acceptance {
    final spec = toolDisplayRegistry[widget.item.presentationContract];
    if (spec == null || !spec.requiresAcceptance) return null;
    final inline = spec.decodeAcceptance(widget.item.output);
    return inline.state != ToolAcceptance.pending
        ? inline
        : _windowAcceptance ?? inline;
  }

  void _retireProjection() {
    _callbackEpoch = Object();
    _windowAcceptance = null;
  }

  @override
  void didUpdateWidget(TimelineToolDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.id != oldWidget.item.id ||
        widget.item.toolCallId != oldWidget.item.toolCallId ||
        widget.item.presentationContract !=
            oldWidget.item.presentationContract ||
        widget.item.statusString != oldWidget.item.statusString ||
        widget.item.output != oldWidget.item.output ||
        widget.declaredContentIdentity != oldWidget.declaredContentIdentity ||
        (widget.declaredContentBuilder == null) !=
            (oldWidget.declaredContentBuilder == null)) {
      _retireProjection();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group = TimelineGroupBodyIntent.of(context);
    if (!identical(group, _group)) {
      _group?.removeListener(_groupChanged);
      _group = group;
      _groupGeneration = group?.bodyGeneration;
      group?.addListener(_groupChanged);
      _retireProjection();
    }
  }

  void _groupChanged() {
    if (identical(_groupGeneration, _group?.bodyGeneration) &&
        _group?.bodyActive == true) {
      return;
    }
    _groupGeneration = _group?.bodyGeneration;
    _retireProjection();
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  void _readOutput(Object epoch, ContentWindow window) {
    if (!mounted ||
        !identical(epoch, _callbackEpoch) ||
        widget.declaredContentBuilder == null ||
        (_group != null && (!_group!.bodyActive || _group!.isRetired)) ||
        !window.sealed ||
        window.offset != 0 ||
        window.bytes.length != window.availableThrough) {
      return;
    }
    final spec = toolDisplayRegistry[widget.item.presentationContract];
    if (spec == null || !spec.requiresAcceptance) return;
    ToolAcceptanceProjection projection;
    try {
      projection = spec.decodeAcceptance(utf8.decode(window.bytes));
    } on FormatException {
      return;
    }
    final previous = _windowAcceptance;
    if (previous?.state == projection.state &&
        previous?.code == projection.code &&
        previous?.reason == projection.reason) {
      return;
    }
    setState(() => _windowAcceptance = projection);
  }

  @override
  void dispose() {
    _group?.removeListener(_groupChanged);
    _retireProjection();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final spec = toolDisplayRegistry[item.presentationContract];
    final epoch = _callbackEpoch;
    final acceptance = _acceptance;
    final declaredContents = widget.declaredContentBuilder?.call(
      (window) => _readOutput(epoch, window),
      acceptance,
    );
    final diagnostics = _toolDiagnostics(context, item, item);
    // A structured-result renderer cannot display a plain execution failure.
    // Keep the authoritative failure message visible when its equal output
    // cannot be decoded, instead of suppressing both as duplicates.
    final outputUnavailable =
        item.error?.trim().isNotEmpty == true &&
        item.error!.trim() == item.output.trim() &&
        spec?.outputFormat == ToolOutputFormat.structured &&
        spec!
            .decodeOutput(context.l10n, item.output)
            .any((value) => value is ToolDetailUnavailable);
    final inputValues =
        spec?.decodeInput(context.l10n, item.arguments) ??
        const <ToolDetailValue>[];
    final artifactValues = [
      if (spec != null)
        for (final artifact in item.outputArtifacts)
          ...spec.artifacts(context.l10n, artifact),
    ];
    final children = <Widget>[
      if (spec == null)
        Text(context.l10n.timelineToolUnknownFormat)
      else ...[
        if (declaredContents == null)
          ?timelineToolInlineBody(
            context,
            item,
            markdownBuilder: widget.markdownBuilder,
            acceptance: acceptance,
          )
        else ...[
          if (spec.inputBody == ToolInputBody.none &&
              !spec.isLsp &&
              inputValues.isNotEmpty)
            TimelineToolSemanticBody(values: inputValues),
          if (spec.inputBody != ToolInputBody.none ||
              spec.readsOutput(item.statusString, output: item.output))
            ...declaredContents,
        ],
      ],
      if (artifactValues.isNotEmpty)
        TimelineToolSemanticBody(values: artifactValues),
      if (diagnostics.isNotEmpty)
        Text(
          diagnostics.join('\n'),
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      if (item.error case final error?
          when error.trim().isNotEmpty &&
              (error.trim() != item.output.trim() ||
                  outputUnavailable ||
                  spec?.readsOutput(item.statusString, output: item.output) ==
                      false))
        Text(
          error,
          style: context.text.bodySmall?.copyWith(
            color: _toolDiagnosticColor(context, item),
          ),
        ),
      if (widget.additionalContentBuilder != null)
        Builder(builder: widget.additionalContentBuilder!),
    ];
    final panel = TimelineBodyReadQualification(
      value: epoch,
      child: TimelineToolDetailPanel(children: children),
    );
    if (widget.inline) {
      return children.isEmpty ? const SizedBox.shrink() : panel;
    }
    final expandable = children.isNotEmpty;
    final tile = TimelineActivityDisclosure(
      key: ValueKey('timeline-tool-details:${item.id}'),
      initiallyExpanded: widget.initiallyExpanded,
      onExpansionChanged: widget.onExpansionChanged,
      enabled: expandable,
      titleBuilder: (context, expanded) =>
          _toolRow(context, expanded: expanded, expandable: expandable),
      children: [panel],
    );
    if (spec?.kind != ToolDetailKind.image) return tile;
    return KeyedSubtree(
      key: StudioDriverKeys.viewImageTool(item.toolCallId),
      child: tile,
    );
  }

  Widget _toolRow(
    BuildContext context, {
    required bool expanded,
    required bool expandable,
  }) {
    final item = widget.item;
    final spec = toolDisplayRegistry[item.presentationContract];
    final targets =
        spec?.rowTarget(context.l10n, item) ?? (label: null, tooltip: null);
    // 只有 exec 的终态行附加本次调用耗时；write_stdin 是写输入而不是进程运行。
    final elapsed =
        toolDisplayRegistry[item.presentationContract]?.elapsed == true
        ? _toolElapsed(item)
        : null;
    return TimelineActivityRow(
      icon: const {'cancelled', 'interrupted'}.contains(item.statusString)
          ? Icons.stop_circle_outlined
          : spec?.icon ?? Icons.build_outlined,
      indicatorStyle: spec?.circularProgress == true
          ? TimelineActivityIndicatorStyle.circularProgress
          : TimelineActivityIndicatorStyle.restingCat,
      label: item.frozenObservation
          ? context.l10n.timelineToolArchivedUnfinished
          : !item.executionPresent &&
                _toolActiveStatuses.contains(item.statusString)
          ? context.l10n.timelineToolNotResumed
          : spec?.rowLabel(
                  context.l10n,
                  item,
                  targets.label,
                  acceptance: _acceptance,
                ) ??
                toolStatusTitle(
                  context.l10n,
                  item.statusString,
                  _unknownToolName(context, item),
                ),
      active:
          item.executionPresent &&
          _toolActiveStatuses.contains(item.statusString),
      isIssue:
          timelineIssueStatuses.contains(item.statusString) ||
          _acceptance?.state == ToolAcceptance.rejected,
      expanded: expanded,
      expandable: expandable,
      meta: elapsed == null
          ? null
          : activityDurationLabel(context, elapsed.inSeconds),
      tooltip: targets.tooltip,
    );
  }
}

/// 展开区只补充真实退出、超时与附件诊断，不重复目标和传输身份。
///
/// 结果与错误各有自己的入口，不在这里重复整段正文。
List<String> _toolDiagnostics(
  BuildContext context,
  TimelineToolPresentation item,
  TimelineToolPresentation? tool,
) {
  return [
        if (tool?.exitCode != null)
          context.l10n.timelineToolExitCode(tool!.exitCode!),
        if (tool?.timedOut == true) context.l10n.timelineToolTimedOut,
        _attachmentDetail(context, tool),
      ]
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .toSet()
      .toList();
}

String? _attachmentDetail(
  BuildContext context,
  TimelineToolPresentation? tool,
) {
  final attachments = tool?.attachments ?? const <ThreadAttachmentView>[];
  if (attachments.isEmpty) return null;
  return attachments
      .map((attachment) => timelineAttachmentDescription(context, attachment))
      .join('\n');
}

/// 本次调用耗时：只取该调用的创建与 canonical 终态时间，不用保存或更新时间。
Duration? _toolElapsed(TimelineToolPresentation item) {
  final createdAt = item.createdAt;
  final completedAt = item.completedAt;
  if (createdAt == null || completedAt == null) return null;
  final elapsed = completedAt.difference(createdAt);
  return elapsed.isNegative ? null : elapsed;
}

/// 取消与中断的原始诊断保留原文，但按正常控制结果用中性色呈现；
/// 真实失败（含拒绝）继续保持错误色醒目。
Color _toolDiagnosticColor(
  BuildContext context,
  TimelineToolPresentation item,
) => switch (item.statusString) {
  'cancelled' || 'interrupted' => context.colors.onSurfaceVariant,
  _ => context.colors.error,
};

const _toolRunningStatuses = {'running', 'streaming', 'approved', 'started'};

const _toolActiveStatuses = {
  'queued',
  ..._toolRunningStatuses,
  'cancelling',
  'awaitingApproval',
};

/// 真正失败、拒绝与预算限制的统一判定：工具行与思考行只替换图标，不改文案
/// 颜色。取消与中断是正常控制结果，保持中性图标与次级色，不算问题。
const timelineIssueStatuses = {'failed', 'denied', 'budgetLimited'};

String timelineToolTitle(BuildContext context, TimelineToolPresentation item) =>
    toolDisplayRegistry[item.presentationContract]?.title(context.l10n, item) ??
    toolStatusTitle(
      context.l10n,
      item.statusString,
      _unknownToolName(context, item),
    );

String _unknownToolName(BuildContext context, TimelineToolPresentation item) =>
    item.name.isEmpty || item.name == 'Tool'
    ? context.l10n.timelineToolFallback
    : item.name;

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
