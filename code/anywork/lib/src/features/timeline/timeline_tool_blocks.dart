part of 'timeline_activity_group_views.dart';

/// 一条工具 Message 的只读展示视图。
///
/// 它只包装这一条 Message 的 typed 事实：名字、状态、参数/结果预览与附件都来自
/// `ThreadItemView.tool`，不另读完整参数 JSON 来推断语义，也不解析私有交互回执
/// （design/26 §26.5、§26.8）。
final class TimelineToolItem {
  const TimelineToolItem(this.entry);

  final TimelineEntry entry;

  TimelineToolPart? get tool => entry.tool;
  String get id => entry.id;
  String get name => tool?.name ?? '';
  String get status => entry.status;
  String get summary => _commandSummary(tool?.arguments ?? '') ?? '';
  String get threadId => entry.threadId;
  String? get error => entry.error;
  DateTime? get createdAt => entry.createdAt;
  DateTime? get completedAt => entry.completedAt;

  /// 同一视图内的只读别名，让既有工具组件直接读单条条目事实。
  TimelineEntry get part => entry;
}

/// 默认显示的工具摘要来源：命令首行 / 路径 / 查询词。
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

bool timelineIsWebSearch(TimelineToolItem item) {
  return item.tool?.name == 'web_search';
}

/// 网页搜索同样是统一轻量行：默认只显示状态文案，查询、链接与结果在展开区。
class TimelineWebSearchToolCard extends StatefulWidget {
  const TimelineWebSearchToolCard({required this.item, super.key});

  final TimelineToolItem item;

  @override
  State<TimelineWebSearchToolCard> createState() =>
      _TimelineWebSearchToolCardState();
}

class _TimelineWebSearchToolCardState extends State<TimelineWebSearchToolCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final data = _WebSearchCardData.fromTool(item.tool);
    final error = item.part.error;
    final result = item.tool?.result;
    final children = <Widget>[
      if (data.details.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            data.details.join('\n'),
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ),
      if (data.links.isNotEmpty) ...[
        Text(
          context.l10n.timelineWebSearchResults,
          style: context.text.labelSmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        for (final link in data.links)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.link, size: 14, color: context.colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    link,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      if (error?.trim().isNotEmpty == true)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            error!,
            style: context.text.bodySmall?.copyWith(
              color: _toolDiagnosticColor(context, item),
            ),
          ),
        )
      else if (result?.trim().isNotEmpty == true)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            result!,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ),
    ];
    return ExpansionTile(
      key: ValueKey('timeline-tool-details:${item.id}'),
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
      title: TimelineActivityRow(
        icon: Icons.travel_explore,
        label: _webSearchLabel(context, item, data),
        active: _toolActiveStatuses.contains(item.status),
        isIssue: timelineIssueStatuses.contains(item.status),
        expandable: children.isNotEmpty,
        expanded: _expanded,
        tooltip: data.details.firstOrNull,
      ),
      children: children,
    );
  }
}

/// 搜索类行的简短文案：成功、失败与进行中各自准确，其它状态保留真实状态。
String _webSearchLabel(
  BuildContext context,
  TimelineToolItem item,
  _WebSearchCardData data,
) {
  final l10n = context.l10n;
  if (item.status == 'succeeded') {
    return switch (data.kind) {
      _WebSearchActionKind.search => l10n.timelineWebSearchSearched,
      _WebSearchActionKind.open => l10n.timelineWebSearchOpened,
      _WebSearchActionKind.find => l10n.timelineWebSearchFound,
      _WebSearchActionKind.other => data.title(context),
    };
  }
  if (item.status == 'failed') {
    return switch (data.kind) {
      _WebSearchActionKind.search ||
      _WebSearchActionKind.other => l10n.timelineWebSearchFailed,
      _WebSearchActionKind.open => l10n.timelineWebSearchOpenFailed,
      _WebSearchActionKind.find => l10n.timelineWebSearchFindFailed,
    };
  }
  if (_toolRunningStatuses.contains(item.status)) return data.title(context);
  return _toolStatusTitle(
    context,
    item.status,
    _toolDisplayName(context, item),
  );
}

enum _WebSearchActionKind { search, open, find, other }

class _WebSearchCardData {
  const _WebSearchCardData({
    required this.kind,
    required this.details,
    required this.links,
  });

  factory _WebSearchCardData.fromTool(TimelineToolPart? tool) {
    final arguments = decodeJsonObject(tool?.arguments ?? '');
    final details = <String>[];
    var kind = _WebSearchActionKind.other;
    final type = arguments['type']?.toString();
    final queries = <String>[];
    final directQuery = arguments['query']?.toString().trim();
    if (directQuery?.isNotEmpty == true) {
      queries.add(directQuery!);
    }
    final actionQueries = arguments['queries'];
    if (actionQueries is List) {
      queries.addAll(
        actionQueries
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty),
      );
    }
    for (final key in const ['search_query', 'image_query']) {
      final commands = arguments[key];
      if (commands is List) {
        for (final command in commands) {
          final query = jsonObject(command)['q']?.toString().trim();
          if (query?.isNotEmpty == true) {
            queries.add(query!);
          }
        }
      }
    }
    if (type == 'search' || queries.isNotEmpty) {
      kind = _WebSearchActionKind.search;
      details.addAll(queries);
    }

    String? url = arguments['url']?.toString();
    final openCommands = arguments['open'];
    if (openCommands is List && openCommands.isNotEmpty) {
      final command = openCommands.first;
      if (command is Map) {
        url = command['ref_id']?.toString();
      }
    }
    if (type == 'open_page' || openCommands is List) {
      kind = _WebSearchActionKind.open;
      if (url?.isNotEmpty == true) details.add(url!);
    }

    String? pattern = arguments['pattern']?.toString();
    final findCommands = arguments['find'];
    if (findCommands is List && findCommands.isNotEmpty) {
      final command = findCommands.first;
      if (command is Map) {
        url = command['ref_id']?.toString();
        pattern = command['pattern']?.toString();
      }
    }
    if (type == 'find_in_page' || findCommands is List) {
      kind = _WebSearchActionKind.find;
      if (url?.isNotEmpty == true) details.add(url!);
      if (pattern?.isNotEmpty == true) details.add(pattern!);
    }

    final links = <String>{};
    for (final artifact in tool?.outputArtifacts ?? const []) {
      _collectWebLinks(artifact, links);
    }
    return _WebSearchCardData(
      kind: kind,
      details: details,
      links: links.take(6).toList(),
    );
  }

  final _WebSearchActionKind kind;
  final List<String> details;
  final List<String> links;

  String title(BuildContext context) {
    return switch (kind) {
      _WebSearchActionKind.search => context.l10n.timelineWebSearchSearching,
      _WebSearchActionKind.open => context.l10n.timelineWebSearchOpening,
      _WebSearchActionKind.find => context.l10n.timelineWebSearchFinding,
      _WebSearchActionKind.other => context.l10n.timelineWebSearchTitle,
    };
  }
}

void _collectWebLinks(Object? value, Set<String> links) {
  if (links.length >= 6) {
    return;
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.startsWith('https://') || trimmed.startsWith('http://')) {
      links.add(trimmed);
    }
    return;
  }
  if (value is List) {
    for (final item in value) {
      _collectWebLinks(item, links);
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      _collectWebLinks(entry.value, links);
    }
  }
}

/// 所有工具共用同一轻量活动行：语义图标、单行状态文案与紧邻文案的箭头。
///
/// 参数、结果、错误、退出码、拒绝原因与附件诊断按需展开，完整字段仍由详情查看器
/// 读取；成功 workflow mutation 的内部 snapshot 继续隐藏（design/19 §19.9）。
class TimelineToolDetails extends StatefulWidget {
  const TimelineToolDetails({
    required this.item,
    this.inline = false,
    super.key,
  });

  final TimelineToolItem item;

  /// 外层已经提供折叠身份（例如接管该行可见性的技能行）时只渲染详情主体，
  /// 不再重复一行工具标题；参数、结果、诊断与错误仍来自同一实现。
  final bool inline;

  @override
  State<TimelineToolDetails> createState() => _TimelineToolDetailsState();
}

class _TimelineToolDetailsState extends State<TimelineToolDetails> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tool = item.tool;
    final hidePayload =
        item.part.status == 'succeeded' &&
        const {'workflow_transition', 'workflow_restart'}.contains(item.name);
    final arguments = hidePayload ? null : tool?.arguments;
    final output = hidePayload ? null : tool?.result;
    final error = item.part.error;
    final showError =
        error != null && error.isNotEmpty && output?.trim() != error.trim();
    final diagnostics = _toolDiagnostics(context, item, tool);
    final children = <Widget>[
      if (diagnostics.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            diagnostics.join('\n'),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              height: 1.4,
              fontFamily: studioCodeFontFamily,
            ),
          ),
        ),
      if (arguments != null && arguments.trim().isNotEmpty)
        StudioCodeBlock(
          text: _prettyToolPayload(arguments),
          language: context.l10n.timelineToolArguments,
          maxHeight: 200,
          margin: const EdgeInsets.only(top: 8),
        ),
      if (output != null && output.trim().isNotEmpty)
        StudioCodeBlock(
          text: _prettyToolPayload(output),
          language: context.l10n.timelineToolOutput,
          maxHeight: 280,
          margin: const EdgeInsets.only(top: 8),
        ),
      if (showError)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            error,
            style: context.text.bodySmall?.copyWith(
              color: _toolDiagnosticColor(context, item),
            ),
          ),
        ),
    ];
    if (widget.inline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    final expandable = children.isNotEmpty;
    final tile = ExpansionTile(
      key: ValueKey('timeline-tool-details:${item.id}'),
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
      title: _toolRow(context, expandable: expandable),
      children: children,
    );
    if (tool?.name != 'view_image') return tile;
    return KeyedSubtree(
      key: StudioDriverKeys.viewImageTool(
        tool?.callId ?? tool?.toolCallId ?? item.part.id,
      ),
      child: tile,
    );
  }

  Widget _toolRow(BuildContext context, {required bool expandable}) {
    final item = widget.item;
    final category = _toolCategory(item.name);
    final targets = _toolRowTargets(context, item, category);
    // 只有 exec 的终态行附加本次调用耗时；write_stdin 是写输入而不是进程运行。
    final elapsed = item.name == 'exec' ? _toolElapsed(item) : null;
    return TimelineActivityRow(
      icon: _toolCategoryIcon(category),
      label: _toolRowLabel(
        context,
        item,
        category,
        targets.label,
        meta: elapsed == null ? null : _toolElapsedLabel(context, elapsed),
      ),
      active: _toolActiveStatuses.contains(item.status),
      isIssue: timelineIssueStatuses.contains(item.status),
      expandable: expandable,
      expanded: _expanded,
      tooltip: targets.tooltip,
    );
  }
}

/// 行内目标与悬浮提示：文件名优先，完整路径／文件列表保留在提示与展开区。
({String? label, String? tooltip}) _toolRowTargets(
  BuildContext context,
  TimelineToolItem item,
  _ToolCategory category,
) {
  // 补丁成功只用工具权威结果预览里的 changedFiles，不在展示层重新解析补丁语法。
  if (item.name == 'apply_patch' && item.status == 'succeeded') {
    final files = _patchChangedFiles(item.tool);
    if (files.isNotEmpty) {
      final first = _lastPathSegment(files.first) ?? files.first;
      return (
        label: files.length == 1
            ? first
            : context.l10n.timelineToolPatchFilesMore(first, files.length - 1),
        tooltip: files.join('\n'),
      );
    }
  }
  // 会话笔记是 Thread 内的固定命名对象，按已知领域名显示，不虚构工作区路径。
  if (item.name == 'apply_session_note_patch' ||
      item.name == 'write_session_note') {
    return (label: context.l10n.timelineSessionNoteName, tooltip: null);
  }
  if (category == _ToolCategory.copy || category == _ToolCategory.move) {
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
  final target = timelineToolTarget(item);
  if (target == null) return (label: null, tooltip: null);
  return (
    label: _showsFileName(category) ? _lastPathSegment(target) : target,
    tooltip: target,
  );
}

/// 文件对象类目的行只显示文件名；命令、搜索等保留原始摘要。
bool _showsFileName(_ToolCategory category) => switch (category) {
  _ToolCategory.read ||
  _ToolCategory.edit ||
  _ToolCategory.create ||
  _ToolCategory.delete ||
  _ToolCategory.copy ||
  _ToolCategory.move => true,
  _ => false,
};

/// 路径的最后一段；没有路径分隔符时原样返回。
String? _lastPathSegment(String? path) {
  if (path == null) return null;
  final segment = path.split(RegExp(r'[/\\]')).last.trim();
  return segment.isEmpty ? path : segment;
}

/// 展开区的次要诊断事实：目标、任务身份、工作目录、退出码与附件说明。
///
/// 结果与错误各有自己的入口，不在这里重复整段正文。
List<String> _toolDiagnostics(
  BuildContext context,
  TimelineToolItem item,
  TimelineToolPart? tool,
) {
  return [
        // 与行内文案同一来源：完整路径／文件列表在展开区仍可读。
        _toolRowTargets(context, item, _toolCategory(item.name)).tooltip,
        tool?.taskId,
        item.summary,
        tool?.workingDirectory,
        if (tool?.exitCode != null)
          context.l10n.timelineToolExitCode(tool!.exitCode!),
        if (tool?.timedOut == true) context.l10n.timelineToolTimedOut,
        tool?.denialReason,
        _attachmentDetail(context, tool),
      ]
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty)
      .toSet()
      .toList();
}

String? _attachmentDetail(BuildContext context, TimelineToolPart? tool) {
  final attachments = tool?.attachments ?? const <ThreadAttachmentView>[];
  if (attachments.isEmpty) return null;
  return attachments
      .map((attachment) => timelineAttachmentDescription(context, attachment))
      .join('\n');
}

Map<String, Object?> _toolArguments(TimelineToolItem item) =>
    decodeJsonObject(item.tool?.arguments ?? '');

/// 目标字段的有界提取：copy/move 取 from→to 的对象，其余沿用既有字段顺序。
String? _targetFromArguments(Map<String, Object?> arguments, String name) {
  final keys = switch (name) {
    'copy_path' || 'move_path' => const ['from', 'to'],
    _ => const [
      'path',
      'filePath',
      'command',
      'cmd',
      'query',
      'pattern',
      'taskSummary',
    ],
  };
  for (final key in keys) {
    final value = _firstLine(jsonStringValue(arguments[key]));
    if (value != null) return value;
  }
  return null;
}

String? timelineToolTarget(TimelineToolItem item) =>
    _targetFromArguments(_toolArguments(item), item.name);

String? _firstLine(String? value) {
  final line = value?.split('\n').first.trim();
  return line == null || line.isEmpty ? null : line;
}

/// 工具结果有界预览里的权威变更文件列表；预览缺失或不完整时不猜测文件名与总数。
List<String> _patchChangedFiles(TimelineToolPart? tool) {
  final result = tool?.result;
  if (result == null || result.trim().isEmpty) return const [];
  final changed = decodeJsonObject(result)['changedFiles'];
  if (changed is! List) return const [];
  return [
    for (final file in changed)
      if (file is String && file.trim().isNotEmpty) file.trim(),
  ];
}

/// 本次调用耗时：只取该调用的创建与 canonical 终态时间，不用保存或更新时间。
Duration? _toolElapsed(TimelineToolItem item) {
  if (!isTerminalTimelineStatus(item.status)) return null;
  return timelineReasoningElapsed(item.createdAt, item.completedAt);
}

String _toolElapsedLabel(BuildContext context, Duration elapsed) {
  final l10n = context.l10n;
  final seconds = elapsed.inSeconds;
  if (seconds <= 0) return l10n.timelineToolElapsedUnderSecond;
  if (seconds < 60) return l10n.timelineToolElapsedSeconds(seconds);
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return remainder == 0
      ? l10n.timelineToolElapsedMinutes(minutes)
      : l10n.timelineToolElapsedMinutesSeconds(minutes, remainder);
}

/// 取消与中断的原始诊断保留原文，但按正常控制结果用中性色呈现；
/// 真实失败（含拒绝）继续保持错误色醒目。
Color _toolDiagnosticColor(BuildContext context, TimelineToolItem item) =>
    switch (item.status) {
      'cancelled' || 'interrupted' => context.colors.onSurfaceVariant,
      _ => context.colors.error,
    };

String _prettyToolPayload(String value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
  } on FormatException {
    return value;
  }
}

/// 工具类目只决定语义图标与动词；状态文案始终来自 canonical 状态。
enum _ToolCategory {
  read,
  edit,
  create,
  delete,
  copy,
  move,
  command,
  stdin,
  search,
  fetch,
  agent,
  message,
  plan,
  planRead,
  workflow,
  workflowRead,
  lsp,
  image,
  wait,
  generic,
}

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
_ToolCategory _toolCategory(String name) => switch (name) {
  'read_session_note' || 'list_files' || 'stat_path' => _ToolCategory.read,
  'apply_patch' ||
  'apply_session_note_patch' ||
  'write_file' ||
  'write_session_note' => _ToolCategory.edit,
  'create_directory' => _ToolCategory.create,
  'delete_path' => _ToolCategory.delete,
  'copy_path' => _ToolCategory.copy,
  'move_path' => _ToolCategory.move,
  'exec' => _ToolCategory.command,
  'write_stdin' => _ToolCategory.stdin,
  'web_search' ||
  'deepseek_web_search' ||
  'search_session_note' => _ToolCategory.search,
  'deepseek_web_fetch' => _ToolCategory.fetch,
  'spawn_agent' => _ToolCategory.agent,
  'send_message' => _ToolCategory.message,
  'wait' || 'sleep' => _ToolCategory.wait,
  'view_image' => _ToolCategory.image,
  _ when name.startsWith('lsp_') => _ToolCategory.lsp,
  'plan_submit' || 'plan_restart' => _ToolCategory.plan,
  'plan_current' || 'plan_next' || 'plan_history' => _ToolCategory.planRead,
  'workflow_transition' || 'workflow_restart' => _ToolCategory.workflow,
  'workflow_current' ||
  'workflow_next' ||
  'workflow_graph' ||
  'workflow_history' => _ToolCategory.workflowRead,
  _ => _ToolCategory.generic,
};

IconData _toolCategoryIcon(_ToolCategory category) => switch (category) {
  _ToolCategory.read => Icons.menu_book_outlined,
  _ToolCategory.edit => Icons.edit_outlined,
  _ToolCategory.create => Icons.create_new_folder_outlined,
  _ToolCategory.delete => Icons.delete_outline,
  _ToolCategory.copy => Icons.content_copy_outlined,
  _ToolCategory.move => Icons.drive_file_move_outline,
  _ToolCategory.command => Icons.terminal,
  _ToolCategory.stdin => Icons.terminal,
  _ToolCategory.search => Icons.search,
  _ToolCategory.fetch => Icons.public,
  _ToolCategory.agent => Icons.account_tree_outlined,
  _ToolCategory.message => Icons.send_outlined,
  _ToolCategory.plan => Icons.checklist_rtl,
  _ToolCategory.planRead => Icons.checklist_rtl,
  _ToolCategory.workflow => Icons.route_outlined,
  _ToolCategory.workflowRead => Icons.route_outlined,
  _ToolCategory.lsp => Icons.code,
  _ToolCategory.image => Icons.image_outlined,
  _ToolCategory.wait => Icons.hourglass_empty,
  _ToolCategory.generic => Icons.build_outlined,
};

/// 成功、失败与进行中的短动词；其它状态返回 null，由调用方保留真实状态文案。
String? _toolVerb(BuildContext context, _ToolCategory category, String status) {
  final l10n = context.l10n;
  final running = _toolRunningStatuses.contains(status);
  final failed = status == 'failed';
  if (!running && !failed && status != 'succeeded') return null;
  return switch (category) {
    _ToolCategory.read =>
      running
          ? l10n.timelineToolReadReading
          : failed
          ? l10n.timelineToolReadFailed
          : l10n.timelineToolReadCompleted,
    _ToolCategory.edit =>
      running
          ? l10n.timelineToolEditRunning
          : failed
          ? l10n.timelineToolEditFailed
          : l10n.timelineToolEditSucceeded,
    _ToolCategory.create =>
      running
          ? l10n.timelineToolCreateRunning
          : failed
          ? l10n.timelineToolCreateFailed
          : l10n.timelineToolCreateSucceeded,
    _ToolCategory.delete =>
      running
          ? l10n.timelineToolDeleteRunning
          : failed
          ? l10n.timelineToolDeleteFailed
          : l10n.timelineToolDeleteSucceeded,
    _ToolCategory.copy =>
      running
          ? l10n.timelineToolCopyRunning
          : failed
          ? l10n.timelineToolCopyFailed
          : l10n.timelineToolCopySucceeded,
    _ToolCategory.move =>
      running
          ? l10n.timelineToolMoveRunning
          : failed
          ? l10n.timelineToolMoveFailed
          : l10n.timelineToolMoveSucceeded,
    _ToolCategory.command =>
      running
          ? l10n.timelineToolCommandRunning
          : failed
          ? l10n.timelineToolCommandFailed
          : l10n.timelineToolCommandSucceeded,
    // 写标准输入不是执行新命令，独立文案也不附加调用耗时。
    _ToolCategory.stdin =>
      running
          ? l10n.timelineToolStdinRunning
          : failed
          ? l10n.timelineToolStdinFailed
          : l10n.timelineToolStdinSucceeded,
    _ToolCategory.search =>
      running
          ? l10n.timelineToolSearchRunning
          : failed
          ? l10n.timelineToolSearchFailed
          : l10n.timelineToolSearchSucceeded,
    _ToolCategory.fetch =>
      running
          ? l10n.timelineToolFetchRunning
          : failed
          ? l10n.timelineToolFetchFailed
          : l10n.timelineToolFetchSucceeded,
    _ToolCategory.agent =>
      running
          ? l10n.timelineToolAgentRunning
          : failed
          ? l10n.timelineToolAgentFailed
          : l10n.timelineToolAgentSucceeded,
    _ToolCategory.message =>
      running
          ? l10n.timelineToolMessageRunning
          : failed
          ? l10n.timelineToolMessageFailed
          : l10n.timelineToolMessageSucceeded,
    _ToolCategory.plan =>
      running
          ? l10n.timelineToolPlanRunning
          : failed
          ? l10n.timelineToolPlanFailed
          : l10n.timelineToolPlanSucceeded,
    _ToolCategory.workflow =>
      running
          ? l10n.timelineToolWorkflowRunning
          : failed
          ? l10n.timelineToolWorkflowFailed
          : l10n.timelineToolWorkflowSucceeded,
    _ToolCategory.lsp =>
      running
          ? l10n.timelineToolLspRunning
          : failed
          ? l10n.timelineToolLspFailed
          : l10n.timelineToolLspSucceeded,
    _ToolCategory.image =>
      running
          ? l10n.timelineViewImageReading
          : failed
          ? l10n.timelineViewImageFailed
          : l10n.timelineViewImageRead,
    _ToolCategory.wait =>
      running
          ? l10n.timelineToolWaitRunning
          : failed
          ? l10n.timelineToolWaitFailed
          : l10n.timelineToolWaitSucceeded,
    // 只读的计划/工作流查询与未知工具沿用“名称＋真实状态”，不猜测成变更。
    _ToolCategory.planRead ||
    _ToolCategory.workflowRead ||
    _ToolCategory.generic => null,
  };
}

/// 行的简短文案：动词＋可选耗时＋目标；没有动词时保留工具名与真实状态。
///
/// 耗时放在目标之前，长命令被行内省略时仍能读到本次调用耗时。
String _toolRowLabel(
  BuildContext context,
  TimelineToolItem item,
  _ToolCategory category,
  String? target, {
  String? meta,
}) {
  final verb = _toolVerb(context, category, item.status);
  if (verb == null) {
    // 排队、取消、拒绝、中断、查询与未知工具都保留工具名，目标只作后缀，
    // 不能用目标顶掉名称而丢掉工具身份与真实状态。
    final base = _toolStatusTitle(
      context,
      item.status,
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

String timelineToolTitle(BuildContext context, TimelineToolItem item) {
  final label = _toolDisplayName(context, item);
  if (item.name == 'view_image') {
    return switch (item.status) {
      'succeeded' => context.l10n.timelineViewImageRead,
      'failed' || 'denied' => context.l10n.timelineViewImageFailed,
      'cancelled' || 'interrupted' => context.l10n.timelineViewImageStopped,
      'queued' ||
      'running' ||
      'streaming' ||
      'approved' ||
      'started' => context.l10n.timelineViewImageReading,
      _ => _unknownToolStatusLabel(context, label, item.status),
    };
  }
  return _toolStatusTitle(context, item.status, label);
}

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
String _toolDisplayName(BuildContext context, TimelineToolItem item) {
  final name = item.name;
  if (name == 'lsp_query') {
    final detail = _lspQueryDetail(item.tool?.arguments ?? '');
    return detail.isEmpty
        ? context.l10n.timelineLspQueryTitle
        : context.l10n.timelineLspQueryTitleWithDetail(detail);
  }
  if (name == 'lsp_capabilities') {
    return context.l10n.timelineLspCapabilitiesTitle;
  }
  if (name.isEmpty || name == 'Tool') {
    return context.l10n.timelineToolFallback;
  }
  return name;
}

/// 从 `lsp_query` 参数中提取 languageId 与查询目标摘要（沿用命令摘要思路）。
String _lspQueryDetail(String arguments) {
  final json = decodeJsonObject(arguments);
  return [
        jsonStringValue(json['languageId']),
        jsonStringValue(json['operation']),
        jsonStringValue(json['filePath']) ??
            jsonStringValue(json['query']) ??
            jsonStringValue(json['path']),
      ]
      .map((value) => value?.trim() ?? '')
      .where((value) => value.isNotEmpty)
      .join(' · ');
}
