part of 'timeline_view.dart';

class _TimelineExpansionScope extends InheritedWidget {
  const _TimelineExpansionScope({
    required this.controllers,
    required super.child,
  });
  final Map<String, ExpansibleController> controllers;
  static ExpansibleController controllerOf(BuildContext context, String id) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_TimelineExpansionScope>()!;
    return scope.controllers.putIfAbsent(id, ExpansibleController.new);
  }

  @override
  bool updateShouldNotify(_TimelineExpansionScope oldWidget) =>
      controllers != oldWidget.controllers;
}

class _ActivityGroupPart extends StatelessWidget {
  const _ActivityGroupPart({required this.group});
  final TimelineActivityGroup group;
  @override
  Widget build(BuildContext context) {
    final controller = _TimelineExpansionScope.controllerOf(context, group.id);
    final current = group.current;
    final label = group.isActive
        ? current.type == TimelineEntryType.tool
              ? _toolTitle(context, TimelineToolItem(part: current))
              : plainReasoningSummary(
                      current.reasoningSummary.firstOrNull ?? '',
                    ) ??
                    context.l10n.timelineReasoningActive
        : group.toolCount == 0
        ? context.l10n.timelineReasoningCompleted
        : '${group.hasReasoning ? context.l10n.timelineActivityTitle : context.l10n.timelineToolGroupTitle} · ${context.l10n.timelineToolGroupSummary(group.toolCount)}';
    final firstIssue = group.firstIssue;
    final issue = firstIssue != null;
    return ExpansionTile(
      key: StudioDriverKeys.timelineActivitySummary(group.id),
      controller: controller,
      initiallyExpanded: controller.isExpanded,
      maintainState: false,
      showTrailingIcon: false,
      minTileHeight: 28,
      dense: true,
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(left: 7, bottom: 6),
      shape: const Border(),
      collapsedShape: const Border(),
      onExpansionChanged: (expanded) => _TimelineItemLayoutScope.report(
        context,
        expanded
            ? _TimelineLayoutChangeKind.expand
            : _TimelineLayoutChangeKind.collapse,
      ),
      title: _TimelineActivitySummary(
        icon: _activityGroupIcon(group, issue: issue),
        label: issue
            ? '${context.toolStatusLabel(firstIssue.status)} · $label'
            : label,
        isIssue: issue,
      ),
      children: [
        DecoratedBox(
          key: const ValueKey('timeline-activity-details'),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: context.colors.outlineVariant),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final part in group.parts)
                  if (part.type == TimelineEntryType.reasoning)
                    _ReasoningActivity(part: part)
                  else
                    _ToolActivity(item: TimelineToolItem(part: part)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

IconData _activityGroupIcon(
  TimelineActivityGroup group, {
  required bool issue,
}) {
  if (issue) return Icons.error_outline;
  if (group.toolCount == 0) return Icons.psychology_alt_outlined;
  final toolParts = group.parts
      .where((part) => part.type == TimelineEntryType.tool)
      .toList(growable: false);
  if (toolParts.length == 1) {
    final name = toolParts.first.tool?.name;
    return switch (name) {
      'exec_command' ||
      'run_command' ||
      'write_stdin' => Icons.terminal_outlined,
      'apply_patch' ||
      'write_file' ||
      'edit_file' ||
      'replace_file_content' ||
      'write_to_file' => Icons.edit_outlined,
      'web_search' ||
      'read_file' ||
      'view_file' ||
      'grep_search' ||
      'find_by_name' ||
      'list_dir' ||
      'lsp_query' ||
      'lsp_capabilities' => Icons.travel_explore_outlined,
      _ => Icons.build_outlined,
    };
  }
  return group.hasReasoning
      ? Icons.psychology_alt_outlined
      : Icons.build_outlined;
}

class _ToolActivity extends StatelessWidget {
  const _ToolActivity({required this.item});
  final TimelineToolItem item;

  @override
  Widget build(BuildContext context) {
    final images = _toolImageEntries([item]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isWebSearch(item))
          _WebSearchToolCard(item: item, embedded: true)
        else
          _ToolDetails(item: item),
        if (images.isNotEmpty)
          _ThreadImageGallery(
            threadId: item.part.threadId,
            entries: images,
            groupId: item.id,
          ),
      ],
    );
  }
}

class _ReasoningActivity extends StatelessWidget {
  const _ReasoningActivity({required this.part});
  final TimelineEntry part;
  @override
  Widget build(BuildContext context) {
    final chunks = part.reasoningContent.isNotEmpty
        ? part.reasoningContent
        : part.reasoningSummary;
    final text = chunks.where((chunk) => chunk.trim().isNotEmpty).join('\n\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: text.isEmpty
          ? Text(context.l10n.timelineReasoningEmpty)
          : _AgentMarkdown(
              id: part.id,
              text: text,
              surface: _MarkdownSurface.reasoning,
            ),
    );
  }
}

class _ImageReadPart extends StatelessWidget {
  const _ImageReadPart({required this.row});
  final TimelineImageRow row;
  @override
  Widget build(BuildContext context) {
    final entries = _toolImageEntries([row.tool]);
    if (entries.isEmpty) {
      return _ToolDetails(item: row.tool);
    }
    return _ThreadImageGallery(
      threadId: row.threadId,
      entries: entries,
      groupId: row.id,
    );
  }
}

bool _isWebSearch(TimelineToolItem item) {
  return item.tool?.name == 'web_search';
}

class _WebSearchToolCard extends StatelessWidget {
  const _WebSearchToolCard({required this.item, this.embedded = false});

  final TimelineToolItem item;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final data = _WebSearchCardData.fromTool(item.tool);
    final content = Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.travel_explore,
                size: 19,
                color: context.colors.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  data.title(context),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.titleSmall?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusPill(label: context.toolStatusLabel(item.status)),
            ],
          ),
          if (data.details.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              data.details.join('\n'),
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
          if (data.links.isNotEmpty) ...[
            const SizedBox(height: 10),
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
          if (item.part.error?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              item.part.error!,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ] else if (item.tool?.result?.trim().isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(
              item.tool!.result!,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
    if (embedded) {
      return Padding(
        padding: const EdgeInsets.only(top: 9),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surfaceContainer,
            borderRadius: BorderRadius.circular(StudioRadii.sm),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: content,
        ),
      );
    }
    return _TimelinePanel(child: content);
  }
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

class _ToolDetails extends StatelessWidget {
  const _ToolDetails({required this.item});

  final TimelineToolItem item;

  @override
  Widget build(BuildContext context) {
    final tool = item.tool;
    final detailLines =
        [
              _toolTarget(item),
              tool?.taskId,
              item.summary,
              tool?.workingDirectory,
              if (tool?.exitCode != null)
                context.l10n.timelineToolExitCode(tool!.exitCode!),
              if (tool?.timedOut == true) context.l10n.timelineToolTimedOut,
              tool?.denialReason,
              item.part.error,
              _resultDetail(item, tool),
              _attachmentDetail(context, tool),
            ]
            .whereType<String>()
            .where((value) => value.trim().isNotEmpty)
            .toSet()
            .toList();
    final hidePayload =
        item.part.status == 'succeeded' &&
        const {'workflow_transition', 'workflow_restart'}.contains(item.name);
    final arguments = hidePayload ? null : tool?.arguments;
    final output = hidePayload ? null : tool?.result;
    return Padding(
      key: tool?.name == 'view_image'
          ? StudioDriverKeys.viewImageTool(
              tool?.callId ?? tool?.toolCallId ?? item.part.id,
            )
          : null,
      padding: const EdgeInsets.only(top: 6),
      child: ExpansionTile(
        key: ValueKey('timeline-tool-details:${item.id}'),
        controller: _TimelineExpansionScope.controllerOf(
          context,
          'tool-details:${item.id}',
        ),
        onExpansionChanged: (expanded) => _TimelineItemLayoutScope.report(
          context,
          expanded
              ? _TimelineLayoutChangeKind.expand
              : _TimelineLayoutChangeKind.collapse,
        ),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        tilePadding: const EdgeInsets.symmetric(horizontal: 8),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          _toolTitle(context, item),
          style: context.text.bodySmall?.copyWith(
            color: context.colors.onSurface,
          ),
        ),
        subtitle: detailLines.isEmpty
            ? null
            : Text(
                detailLines.join('\n'),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
        children: [
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
          if (item.part.error?.isNotEmpty == true &&
              output?.trim() != item.part.error?.trim())
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                item.part.error!,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _resultDetail(TimelineToolItem item, TimelineToolPart? tool) {
    final result = tool?.result;
    if (result == null || result.trim().isEmpty) {
      return null;
    }
    if (item.part.status == 'succeeded') {
      return null;
    }
    if (item.name == 'workflow_transition' || item.name == 'workflow_restart') {
      return _workflowMutationDetail(result);
    }
    return result;
  }

  String _workflowMutationDetail(String result) {
    try {
      final decoded = jsonDecode(result);
      if (decoded is! Map) return result;
      final code = decoded['code']?.toString();
      final recoveryAction = decoded['recoveryAction']?.toString();
      final lines = <String>[
        if (code?.trim().isNotEmpty == true) code!,
        if (recoveryAction?.trim().isNotEmpty == true) recoveryAction!,
      ];
      return lines.isEmpty ? result : lines.join('\n');
    } catch (_) {
      return result;
    }
  }

  String? _attachmentDetail(BuildContext context, TimelineToolPart? tool) {
    final attachments = tool?.attachments ?? const <ThreadAttachmentView>[];
    if (attachments.isEmpty) return null;
    return attachments
        .map((attachment) => _attachmentDescription(context, attachment))
        .join('\n');
  }
}

String? _toolTarget(TimelineToolItem item) {
  final arguments = decodeJsonObject(item.tool?.arguments ?? '');
  for (final key in const [
    'path',
    'filePath',
    'command',
    'cmd',
    'query',
    'pattern',
  ]) {
    final value = jsonStringValue(arguments[key])?.trim();
    if (value != null && value.isNotEmpty) return value.split('\n').first;
  }
  return null;
}

String _prettyToolPayload(String value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
  } on FormatException {
    return value;
  }
}

String _toolTitle(BuildContext context, TimelineToolItem item) {
  final label = _toolDisplayName(context, item);
  if (item.name == 'view_image') {
    return switch (item.status) {
      'succeeded' => context.l10n.timelineViewImageRead,
      'failed' ||
      'denied' ||
      'cancelled' ||
      'interrupted' => context.l10n.timelineViewImageFailed,
      'queued' ||
      'running' ||
      'streaming' ||
      'approved' ||
      'started' => context.l10n.timelineViewImageReading,
      _ => _unknownToolStatusLabel(context, label, item.status),
    };
  }
  return switch (item.status) {
    'queued' => context.l10n.timelineToolQueued(label),
    'cancelling' => context.l10n.timelineToolCancelling(label),
    'interrupted' => context.l10n.timelineToolInterrupted(label),
    'succeeded' => context.l10n.timelineToolCompleted(label),
    'failed' => context.l10n.timelineToolFailed(label),
    'denied' => context.l10n.timelineToolDenied(label),
    'cancelled' => context.l10n.timelineToolCancelled(label),
    'awaitingApproval' => context.l10n.timelineToolAwaitingApproval(label),
    'running' ||
    'streaming' ||
    'approved' ||
    'started' => context.l10n.timelineToolRunning(label),
    _ => _unknownToolStatusLabel(context, label, item.status),
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
