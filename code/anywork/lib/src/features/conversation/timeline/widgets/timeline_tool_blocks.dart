import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:anywork_client/models.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../../../shared/typed_json.dart';
import '../state/lsp_presentation.dart';
import '../state/tool_presentation.dart';
import '../state/tool_display_registry.dart';
import '../state/timeline_display_unit.dart';
import 'timeline_activity_row.dart';
import 'timeline_content_range_view.dart' show TimelineBodyReadQualification;
import 'timeline_activity_clock.dart';
import 'timeline_lsp_tool_view.dart';
import 'timeline_patch_diff_view.dart';
import 'timeline_tool_detail_panel.dart';

/// 保留调用入口，网页搜索与其他工具共用登记、活动行和详情面板。
class TimelineWebSearchToolCard extends StatelessWidget {
  const TimelineWebSearchToolCard({
    required this.item,
    this.initiallyExpanded = false,
    this.onExpansionChanged,
    super.key,
  });
  final TimelineToolPresentation item;
  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  @override
  Widget build(BuildContext context) => TimelineToolDetails(
    item: item,
    initiallyExpanded: initiallyExpanded,
    onExpansionChanged: onExpansionChanged,
  );
}

bool timelineIsWebSearch(TimelineToolPresentation item) =>
    toolDisplayRegistry[item.presentationContract]?.kind == ToolDetailKind.web;

/// 内联正文和声明窗口都经过同一登记，不直接公开参数信封。
Widget? timelineToolInlineBody(
  TimelineToolPresentation item, {
  TimelineLspMarkdownBuilder? markdownBuilder,
  ToolAcceptanceProjection? acceptance,
}) {
  final spec = toolDisplayRegistry[item.presentationContract];
  if (spec == null) return const Text('未知工具展示格式');
  if (spec.isLsp) {
    return timelineLspInlineBody(item, markdownBuilder: markdownBuilder);
  }
  final inputValues = spec.decodeInput(item.arguments);
  final outputValues = spec.readsOutput(item.statusString, output: item.output)
      ? acceptance != null && acceptance.state != ToolAcceptance.pending
            ? spec.acceptanceDetails(acceptance)
            : spec.decodeOutput(item.output)
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
  TimelineToolPresentation item,
  String text, {
  required bool input,
  TimelineLspMarkdownBuilder? markdownBuilder,
  ToolAcceptanceProjection? acceptance,
}) {
  final spec = toolDisplayRegistry[item.presentationContract];
  if (spec == null) return const Text('未知工具展示格式');
  if (input && spec.inputBody == ToolInputBody.patch) {
    return timelineApplyPatchWindowBody(text);
  }
  if (!input && spec.isLsp) {
    return timelineLspWindowBody(item, text, markdownBuilder: markdownBuilder);
  }
  if (!input && spec.requiresAcceptance) {
    return TimelineToolSemanticBody(
      values: spec.acceptanceDetails(
        acceptance ?? const ToolAcceptanceProjection(ToolAcceptance.pending),
      ),
    );
  }
  if (!input &&
      spec.outputFormat == ToolOutputFormat.structured &&
      text.trim().isEmpty) {
    return const TimelineToolSemanticBody(
      values: [ToolDetailUnavailable('结构化结果不可用：窗口不完整或格式错误')],
    );
  }
  return TimelineToolSemanticBody(
    values: input ? spec.decodeInput(text) : spec.decodeOutput(text),
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
    final inputValues =
        spec?.decodeInput(item.arguments) ?? const <ToolDetailValue>[];
    final artifactValues = [
      if (spec != null)
        for (final artifact in item.outputArtifacts)
          ...spec.artifacts(artifact),
    ];
    final children = <Widget>[
      if (spec == null)
        const Text('未知工具展示格式')
      else ...[
        if (declaredContents == null)
          ?timelineToolInlineBody(
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
    final category = _toolCategory(item);
    final targets = _toolRowTargets(context, item, category);
    // 只有 exec 的终态行附加本次调用耗时；write_stdin 是写输入而不是进程运行。
    final elapsed =
        toolDisplayRegistry[item.presentationContract]?.elapsed == true
        ? _toolElapsed(item)
        : null;
    final isExecCommand = category == ToolDisplayCategory.command;
    return TimelineActivityRow(
      icon: const {'cancelled', 'interrupted'}.contains(item.statusString)
          ? Icons.stop_circle_outlined
          : _toolCategoryIcon(category),
      indicatorStyle: isExecCommand
          ? TimelineActivityIndicatorStyle.circularProgress
          : TimelineActivityIndicatorStyle.restingCat,
      label: item.frozenObservation
          ? '封存时尚未结束'
          : !item.executionPresent &&
                _toolActiveStatuses.contains(item.statusString)
          ? '工具尚未恢复'
          : _toolRowLabel(
              context,
              item,
              category,
              targets.label,
              acceptance: _acceptance,
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

/// 行内目标与悬浮提示；补丁文件身份只由 diff 本身呈现。
({String? label, String? tooltip}) _toolRowTargets(
  BuildContext context,
  TimelineToolPresentation item,
  ToolDisplayCategory category,
) {
  // 会话笔记是 Thread 内的固定命名对象，按已知领域名显示，不虚构工作区路径。
  if (toolDisplayRegistry[item.presentationContract]?.sessionNote == true) {
    return (label: context.l10n.timelineSessionNoteName, tooltip: null);
  }
  if (category == ToolDisplayCategory.copy ||
      category == ToolDisplayCategory.move) {
    final arguments = _toolArguments(item);
    final from = _firstLine(jsonStringValue(arguments['from']));
    final to = _firstLine(jsonStringValue(arguments['to']));
    if (from != null || to != null) {
      final names = [
        if (from != null) _lastPathSegment(from),
        if (to != null) _lastPathSegment(to),
      ].whereType<String>().join(' → ');
      return (
        label: names.isEmpty ? null : names,
        tooltip: [?from, if (to != null) '→ $to'].join('\n'),
      );
    }
  }
  if (toolDisplayRegistry[item.presentationContract]?.kind ==
      ToolDetailKind.lspQuery) {
    return _lspQueryRowTargets(item);
  }
  final target = timelineToolTarget(item);
  if (target == null) return (label: null, tooltip: null);
  return (
    label: _showsFileName(category) ? _lastPathSegment(target) : target,
    tooltip: target,
  );
}

({String? label, String? tooltip}) _lspQueryRowTargets(
  TimelineToolPresentation item,
) {
  final args = _toolArguments(item);
  final filePath = _firstLine(jsonStringValue(args['filePath']));
  final line = switch (args['line']) {
    final int n => n,
    final num n => n.toInt(),
    final String s => int.tryParse(s.trim()),
    _ => null,
  };
  final character = switch (args['character']) {
    final int n => n,
    final num n => n.toInt(),
    final String s => int.tryParse(s.trim()),
    _ => null,
  };
  if (filePath != null) {
    final shortName = _lastPathSegment(filePath) ?? filePath;
    final lineSuffix = (line != null && line > 0) ? ':$line' : '';
    final fullCoord = (line != null && line > 0)
        ? (character != null && character > 0 ? ':$line:$character' : ':$line')
        : '';
    return (label: '$shortName$lineSuffix', tooltip: '$filePath$fullCoord');
  }
  final query = _firstLine(jsonStringValue(args['query']));
  if (query != null) {
    return (label: query, tooltip: query);
  }
  final languageId = _firstLine(jsonStringValue(args['languageId']));
  if (languageId != null) {
    return (label: languageId, tooltip: languageId);
  }
  return (label: null, tooltip: null);
}

/// 文件对象类目的行只显示文件名；命令、搜索等保留原始摘要。
bool _showsFileName(ToolDisplayCategory category) => switch (category) {
  ToolDisplayCategory.read ||
  ToolDisplayCategory.edit ||
  ToolDisplayCategory.create ||
  ToolDisplayCategory.delete ||
  ToolDisplayCategory.copy ||
  ToolDisplayCategory.move => true,
  _ => false,
};

/// 路径的最后一段；没有路径分隔符时原样返回。
String? _lastPathSegment(String? path) {
  if (path == null) return null;
  final segment = path.split(RegExp(r'[/\\]')).last.trim();
  return segment.isEmpty ? path : segment;
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

Map<String, Object?> _toolArguments(TimelineToolPresentation item) =>
    decodeJsonObject(item.arguments);

/// 目标字段的有界提取：copy/move 取 from→to 的对象，其余沿用既有字段顺序。
String? timelineToolTarget(TimelineToolPresentation item) {
  final keys =
      toolDisplayRegistry[item.presentationContract]?.targetFields ??
      const <String>[];
  if (keys.isEmpty) return null;
  final arguments = _toolArguments(item);
  for (final key in keys) {
    final value = _firstLine(jsonStringValue(arguments[key]));
    if (value != null) return value;
  }
  return null;
}

String? _firstLine(String? value) {
  final line = value?.split('\n').first.trim();
  return line == null || line.isEmpty ? null : line;
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

/// 工具名到展示类目的有界映射；未知工具保留名称与真实状态，不猜测语义。
///
/// 只读的计划/工作流查询保留语义图标但沿用“名称＋真实状态”文案，避免把查询说成
/// 变更；删除、复制、移动与新建各自独立，不笼统归入“已修改”。
ToolDisplayCategory _toolCategory(TimelineToolPresentation item) =>
    toolDisplayRegistry[item.presentationContract]?.category ??
    ToolDisplayCategory.generic;

IconData _toolCategoryIcon(ToolDisplayCategory category) => switch (category) {
  ToolDisplayCategory.read => Icons.menu_book_outlined,
  ToolDisplayCategory.edit => Icons.edit_outlined,
  ToolDisplayCategory.create => Icons.create_new_folder_outlined,
  ToolDisplayCategory.delete => Icons.delete_outline,
  ToolDisplayCategory.copy => Icons.content_copy_outlined,
  ToolDisplayCategory.move => Icons.drive_file_move_outline,
  ToolDisplayCategory.command => Icons.terminal,
  ToolDisplayCategory.stdin => Icons.terminal,
  ToolDisplayCategory.search => Icons.search,
  ToolDisplayCategory.fetch => Icons.public,
  ToolDisplayCategory.agent => Icons.account_tree_outlined,
  ToolDisplayCategory.message => Icons.send_outlined,
  ToolDisplayCategory.plan => Icons.checklist_rtl,
  ToolDisplayCategory.planRead => Icons.checklist_rtl,
  ToolDisplayCategory.workflow => Icons.route_outlined,
  ToolDisplayCategory.workflowRead => Icons.route_outlined,
  ToolDisplayCategory.lsp => Icons.code,
  ToolDisplayCategory.image => Icons.image_outlined,
  ToolDisplayCategory.wait => Icons.hourglass_empty,
  ToolDisplayCategory.generic => Icons.build_outlined,
};

/// 成功、失败与进行中的短动词；其它状态返回 null，由调用方保留真实状态文案。
String? _toolVerb(
  BuildContext context,
  TimelineToolPresentation item,
  ToolDisplayCategory category,
  String status,
) {
  final l10n = context.l10n;
  final running = _toolRunningStatuses.contains(status);
  final failed = status == 'failed';
  if (!running && !failed && status != 'succeeded') return null;
  if (toolDisplayRegistry[item.presentationContract]?.kind ==
      ToolDetailKind.web) {
    final action = timelineToolWebAction(item.arguments);
    return switch (action) {
      ToolWebAction.search || ToolWebAction.other =>
        running
            ? l10n.timelineWebSearchSearching
            : failed
            ? l10n.timelineWebSearchFailed
            : l10n.timelineWebSearchSearched,
      ToolWebAction.open =>
        running
            ? l10n.timelineWebSearchOpening
            : failed
            ? l10n.timelineWebSearchOpenFailed
            : l10n.timelineWebSearchOpened,
      ToolWebAction.find =>
        running
            ? l10n.timelineWebSearchFinding
            : failed
            ? l10n.timelineWebSearchFindFailed
            : l10n.timelineWebSearchFound,
    };
  }
  if (category == ToolDisplayCategory.lsp) {
    return _lspToolVerb(context, item, running: running, failed: failed);
  }
  return switch (category) {
    ToolDisplayCategory.read =>
      running
          ? l10n.timelineToolReadReading
          : failed
          ? l10n.timelineToolReadFailed
          : l10n.timelineToolReadCompleted,
    ToolDisplayCategory.edit =>
      running
          ? l10n.timelineToolEditRunning
          : failed
          ? l10n.timelineToolEditFailed
          : l10n.timelineToolEditSucceeded,
    ToolDisplayCategory.create =>
      running
          ? l10n.timelineToolCreateRunning
          : failed
          ? l10n.timelineToolCreateFailed
          : l10n.timelineToolCreateSucceeded,
    ToolDisplayCategory.delete =>
      running
          ? l10n.timelineToolDeleteRunning
          : failed
          ? l10n.timelineToolDeleteFailed
          : l10n.timelineToolDeleteSucceeded,
    ToolDisplayCategory.copy =>
      running
          ? l10n.timelineToolCopyRunning
          : failed
          ? l10n.timelineToolCopyFailed
          : l10n.timelineToolCopySucceeded,
    ToolDisplayCategory.move =>
      running
          ? l10n.timelineToolMoveRunning
          : failed
          ? l10n.timelineToolMoveFailed
          : l10n.timelineToolMoveSucceeded,
    ToolDisplayCategory.command =>
      running
          ? l10n.timelineToolCommandRunning
          : failed
          ? l10n.timelineToolCommandFailed
          : l10n.timelineToolCommandSucceeded,
    // 写标准输入不是执行新命令，独立文案也不附加调用耗时。
    ToolDisplayCategory.stdin =>
      running
          ? l10n.timelineToolStdinRunning
          : failed
          ? l10n.timelineToolStdinFailed
          : l10n.timelineToolStdinSucceeded,
    ToolDisplayCategory.search =>
      running
          ? l10n.timelineToolSearchRunning
          : failed
          ? l10n.timelineToolSearchFailed
          : l10n.timelineToolSearchSucceeded,
    ToolDisplayCategory.fetch =>
      running
          ? l10n.timelineToolFetchRunning
          : failed
          ? l10n.timelineToolFetchFailed
          : l10n.timelineToolFetchSucceeded,
    ToolDisplayCategory.agent =>
      running
          ? l10n.timelineToolAgentRunning
          : failed
          ? l10n.timelineToolAgentFailed
          : l10n.timelineToolAgentSucceeded,
    ToolDisplayCategory.message =>
      running
          ? l10n.timelineToolMessageRunning
          : failed
          ? l10n.timelineToolMessageFailed
          : l10n.timelineToolMessageSucceeded,
    ToolDisplayCategory.plan =>
      running
          ? l10n.timelineToolPlanRunning
          : failed
          ? l10n.timelineToolPlanFailed
          : l10n.timelineToolPlanSucceeded,
    ToolDisplayCategory.workflow =>
      running
          ? l10n.timelineToolWorkflowRunning
          : failed
          ? l10n.timelineToolWorkflowFailed
          : l10n.timelineToolWorkflowSucceeded,
    ToolDisplayCategory.lsp =>
      running
          ? l10n.timelineToolLspRunning
          : failed
          ? l10n.timelineToolLspFailed
          : l10n.timelineToolLspSucceeded,
    ToolDisplayCategory.image =>
      running
          ? l10n.timelineViewImageReading
          : failed
          ? l10n.timelineViewImageFailed
          : l10n.timelineViewImageRead,
    ToolDisplayCategory.wait =>
      running
          ? l10n.timelineToolWaitRunning
          : failed
          ? l10n.timelineToolWaitFailed
          : l10n.timelineToolWaitSucceeded,
    // 只读的计划/工作流查询与未知工具沿用“名称＋真实状态”，不猜测成变更。
    ToolDisplayCategory.planRead ||
    ToolDisplayCategory.workflowRead ||
    ToolDisplayCategory.generic => null,
  };
}

String _lspToolVerb(
  BuildContext context,
  TimelineToolPresentation item, {
  required bool running,
  required bool failed,
}) {
  final l10n = context.l10n;
  if (toolDisplayRegistry[item.presentationContract]?.kind ==
      ToolDetailKind.lspCapabilities) {
    return running
        ? l10n.timelineLspCapabilitiesRunning
        : failed
        ? l10n.timelineLspCapabilitiesFailed
        : l10n.timelineLspCapabilitiesSucceeded;
  }
  if (toolDisplayRegistry[item.presentationContract]?.kind ==
      ToolDetailKind.lspStatus) {
    return running
        ? l10n.timelineLspStatusRunning
        : failed
        ? l10n.timelineLspStatusFailed
        : l10n.timelineLspStatusSucceeded;
  }
  return switch (timelineLspQueryOperation(item)) {
    TimelineLspOperation.goToDefinition =>
      running
          ? l10n.timelineLspOpDefinitionRunning
          : failed
          ? l10n.timelineLspOpDefinitionFailed
          : l10n.timelineLspOpDefinitionSucceeded,
    TimelineLspOperation.goToImplementation =>
      running
          ? l10n.timelineLspOpImplementationRunning
          : failed
          ? l10n.timelineLspOpImplementationFailed
          : l10n.timelineLspOpImplementationSucceeded,
    TimelineLspOperation.findReferences =>
      running
          ? l10n.timelineLspOpReferencesRunning
          : failed
          ? l10n.timelineLspOpReferencesFailed
          : l10n.timelineLspOpReferencesSucceeded,
    TimelineLspOperation.hover =>
      running
          ? l10n.timelineLspOpHoverRunning
          : failed
          ? l10n.timelineLspOpHoverFailed
          : l10n.timelineLspOpHoverSucceeded,
    TimelineLspOperation.documentSymbol =>
      running
          ? l10n.timelineLspOpDocumentSymbolRunning
          : failed
          ? l10n.timelineLspOpDocumentSymbolFailed
          : l10n.timelineLspOpDocumentSymbolSucceeded,
    TimelineLspOperation.workspaceSymbol =>
      running
          ? l10n.timelineLspOpWorkspaceSymbolRunning
          : failed
          ? l10n.timelineLspOpWorkspaceSymbolFailed
          : l10n.timelineLspOpWorkspaceSymbolSucceeded,
    TimelineLspOperation.prepareCallHierarchy ||
    TimelineLspOperation.incomingCalls ||
    TimelineLspOperation.outgoingCalls =>
      running
          ? l10n.timelineLspOpCallHierarchyRunning
          : failed
          ? l10n.timelineLspOpCallHierarchyFailed
          : l10n.timelineLspOpCallHierarchySucceeded,
    TimelineLspOperation.diagnostics =>
      running
          ? l10n.timelineLspOpDiagnosticsRunning
          : failed
          ? l10n.timelineLspOpDiagnosticsFailed
          : l10n.timelineLspOpDiagnosticsSucceeded,
    TimelineLspOperation.unknown =>
      running
          ? l10n.timelineToolLspRunning
          : failed
          ? l10n.timelineToolLspFailed
          : l10n.timelineToolLspSucceeded,
  };
}

/// 行的简短文案：动词＋可选耗时＋目标；没有动词时保留工具名与真实状态。
///
/// 耗时放在目标之前，长命令被行内省略时仍能读到本次调用耗时。
String _toolRowLabel(
  BuildContext context,
  TimelineToolPresentation item,
  ToolDisplayCategory category,
  String? target, {
  String? meta,
  ToolAcceptanceProjection? acceptance,
}) {
  final spec = toolDisplayRegistry[item.presentationContract];
  if (spec != null &&
      spec.requiresAcceptance &&
      item.statusString == 'succeeded') {
    final projection = acceptance ?? spec.decodeAcceptance(item.output);
    final label = switch (projection.state) {
      ToolAcceptance.pending => '结果待确认',
      ToolAcceptance.rejected => _toolRejectionLabel(spec),
      ToolAcceptance.accepted => null,
    };
    if (label != null) return [label, ?target].join(' ');
  }
  final verb = _toolVerb(context, item, category, item.statusString);
  if (verb == null) {
    // 排队、取消、拒绝、中断、查询与未知工具都保留工具名，目标只作后缀，
    // 不能用目标顶掉名称而丢掉工具身份与真实状态。
    final base = _toolStatusTitle(
      context,
      item.statusString,
      _toolDisplayName(context, item),
    );
    return [
      base,
      ?meta,
      if (target != null && target.isNotEmpty) target,
    ].join(' · ');
  }
  if (meta != null) {
    return [
      verb,
      meta,
      if (target != null && target.isNotEmpty) target,
    ].join(' · ');
  }
  if (target == null || target.isEmpty) return verb;
  return '$verb $target';
}

String timelineToolTitle(BuildContext context, TimelineToolPresentation item) {
  final spec = toolDisplayRegistry[item.presentationContract];
  if (spec != null &&
      spec.requiresAcceptance &&
      item.statusString == 'succeeded') {
    switch (spec.decodeAcceptance(item.output).state) {
      case ToolAcceptance.pending:
        return '结果待确认';
      case ToolAcceptance.rejected:
        return _toolRejectionLabel(spec);
      case ToolAcceptance.accepted:
        break;
    }
  }
  final label = _toolDisplayName(context, item);
  if (toolDisplayRegistry[item.presentationContract]?.kind ==
      ToolDetailKind.image) {
    return switch (item.statusString) {
      'succeeded' => context.l10n.timelineViewImageRead,
      'failed' || 'denied' => context.l10n.timelineViewImageFailed,
      'cancelled' || 'interrupted' => context.l10n.timelineViewImageStopped,
      'queued' ||
      'running' ||
      'streaming' ||
      'approved' ||
      'started' => context.l10n.timelineViewImageReading,
      _ => _unknownToolStatusLabel(context, label, item.statusString),
    };
  }
  return _toolStatusTitle(context, item.statusString, label);
}

String _toolRejectionLabel(ToolDisplaySpec spec) => spec.rejectionLabel;

String _toolStatusTitle(BuildContext context, String status, String name) {
  return switch (status) {
    'queued' => context.l10n.timelineToolQueued(name),
    'cancelling' => context.l10n.timelineToolCancelling(name),
    'interrupted' => context.l10n.timelineToolInterrupted(name),
    'succeeded' => context.l10n.timelineToolCompleted(name),
    'failed' => context.l10n.timelineToolFailed(name),
    'denied' => context.l10n.timelineToolDenied(name),
    'cancelled' => context.l10n.timelineToolCancelled(name),
    'awaitingApproval' => context.l10n.timelineToolAwaitingApproval(name),
    'running' ||
    'streaming' ||
    'approved' ||
    'started' => context.l10n.timelineToolRunning(name),
    _ => _unknownToolStatusLabel(context, name, status),
  };
}

/// 未知工具状态保留原始值，并让缺失的工具名回退到统一 fallback；不把未知
/// 状态伪装成某个已知阶段。
String _unknownToolStatusLabel(
  BuildContext context,
  String name,
  String status,
) {
  final resolvedName = name.trim().isEmpty
      ? context.l10n.timelineToolFallback
      : name;
  if (status.trim().isEmpty) {
    return resolvedName;
  }
  return context.l10n.timelineToolUnknownStatus(resolvedName, status);
}

/// 工具的展示名；LSP 工具使用本地化标题并附带参数摘要，其余保持原始领域名。
String _toolDisplayName(BuildContext context, TimelineToolPresentation item) {
  final name = item.name;
  if (toolDisplayRegistry[item.presentationContract]?.kind ==
      ToolDetailKind.lspQuery) {
    final detail = _lspQueryDetail(context, item.arguments);
    return detail.isEmpty
        ? context.l10n.timelineLspQueryTitle
        : context.l10n.timelineLspQueryTitleWithDetail(detail);
  }
  if (toolDisplayRegistry[item.presentationContract]?.kind ==
      ToolDetailKind.lspCapabilities) {
    return context.l10n.timelineLspCapabilitiesTitle;
  }
  if (toolDisplayRegistry[item.presentationContract]?.kind ==
      ToolDetailKind.lspStatus) {
    return context.l10n.timelineLspStatusTitle;
  }
  if (name.isEmpty || name == 'Tool') {
    return context.l10n.timelineToolFallback;
  }
  return name;
}

/// 从 `lsp_query` 参数中提取本地化操作与查询目标摘要。
String _lspQueryDetail(BuildContext context, String arguments) {
  final json = decodeJsonObject(arguments);
  final rawOp = jsonStringValue(json['operation']);
  final op = TimelineLspOperation.fromWire(rawOp);
  final opLabel = rawOp == null
      ? ''
      : timelineLspOperationLabel(context.l10n, op, raw: rawOp);
  return [
        opLabel,
        jsonStringValue(json['languageId']),
        jsonStringValue(json['filePath']),
        jsonStringValue(json['query']),
      ]
      .map((value) => value?.trim() ?? '')
      .where((value) => value.isNotEmpty)
      .join(' · ');
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
