import 'dart:convert';

import 'package:anywork_client/models.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../../shared/studio_code_block.dart';
import '../../connectors/timeline_feed_body_connector.dart';
import '../../state/chat_item_presentation.dart';
import '../../state/chat_payload_reading.dart';
import '../../state/timeline_feed_projection.dart';
import '../../state/tool_presentation.dart';
import '../../tools/support/tool_status_labels.dart';
import '../../tools/tool_item_registry.dart';
import '../../tools/tool_item_view.dart';
import '../../widgets/content_layout_witness.dart';
import '../../widgets/timeline_activity_row.dart';
import '../../widgets/timeline_content_range_view.dart';
import '../../widgets/timeline_plain_text.dart';
import '../work_group_member_adapter.dart';

const _commandToolNames = {
  'exec',
  'exec_command',
  'shell',
  'write_stdin',
  'bash',
};

/// 将 [WorkGroupToolCall] 归一为 [TimelineToolPresentation]，供实时工作组与历史工作组共用。
///
/// 优先使用 `timelineFeedMember(member)` 解码完整载荷；若 `payloadJson` 为空或缺少
/// `invocation`（例如实时轻量流式原子或精简测试样例），直接从成员字段构造合法卡片。
TimelineToolPresentation workGroupToolPresentationFromMember(
  WorkGroupToolCall member, {
  ChatItemPresentation? presentation,
  String? argumentsOverride,
  bool isLive = false,
}) {
  final item = presentation ?? timelineFeedMember(member);
  final reading = argumentsOverride == null
      ? item.toolCard
      : readToolCard(item, arguments: argumentsOverride);
  if (reading is DecodedToolCard) {
    return _enrichToolTimestamps(reading.value, member);
  }

  final statusString = _normalizeToolStatus(member.status);
  final rawArgs = argumentsOverride ?? member.arguments ?? '';
  final effectiveArgs =
      rawArgs.trim().isEmpty &&
          member.summary.trim().isNotEmpty &&
          member.summary.trim() != member.toolName &&
          _commandToolNames.contains(member.toolName)
      ? jsonEncode({'command': member.summary.trim()})
      : rawArgs;
  final hasResultRef = member.bodies.any((b) => b.bodyKey == 'tool.result');
  final activeTailOnly =
      isLive && isTimelineToolActive(statusString) && !hasResultRef;

  return TimelineToolPresentation(
    id: member.id,
    toolCallId: member.callId,
    name: member.toolName,
    presentationContract: member.presentationContract ?? '',
    statusString: statusString,
    arguments: effectiveArgs,
    output: activeTailOnly ? '' : (member.resultPreview ?? ''),
    createdAt: _millisToDateTime(member.startedAtMs),
    completedAt: _millisToDateTime(member.finishedAtMs),
    wait: _decodeWaitJson(member.waitJson),
  );
}

/// 渲染工作组内的工具调用，直接复用 [TimelineToolItemView] 与 [timelineToolItemRegistry]。
class ToolMemberItem extends WorkGroupMemberAdapter {
  const ToolMemberItem();

  @override
  String get id => 'work_group.tool_call';

  @override
  WorkGroupMemberMatcher get matcher =>
      const WorkGroupMemberMatcher.kind(WorkGroupMemberKind.toolCall);

  @override
  Widget build(WorkGroupMemberContext context) {
    final member = context.member as WorkGroupToolCall;
    final item = timelineFeedMember(member);
    return _buildForItem(context, member, item);
  }

  Widget _buildForItem(
    WorkGroupMemberContext context,
    WorkGroupToolCall member,
    ChatItemPresentation item, {
    String? argumentsOverride,
  }) {
    final argumentBody = item.body('tool.arguments');
    if (argumentBody?.feedReference case final reference?
        when argumentsOverride == null &&
            argumentBody!.hasInline == false &&
            reference.byteLength <= timelineBodyWindowMaxBytes) {
      return TimelineFeedBodyConnector(
        itemId: item.id,
        reference: reference,
        label: context.l10n.timelineToolArguments,
        disclosed: true,
        witness: (_, child) => child,
        bodyBuilder: (text) {
          if (utf8.encode(text).length != reference.byteLength) {
            return _unavailable(
              context.l10n.timelineToolArgumentsIncompleteTitle,
              context.l10n.timelineToolArgumentsIncompleteDetail,
            );
          }
          return _buildForItem(context, member, item, argumentsOverride: text);
        },
      );
    }

    final reading = argumentsOverride == null
        ? item.toolCard
        : readToolCard(item, arguments: argumentsOverride);

    if (reading is UnavailableToolCard &&
        _hasToolEnvelope(member.payloadJson)) {
      final invocation = item.data['invocation'];
      final name =
          invocation is Map<String, Object?> && invocation['name'] is String
          ? invocation['name'] as String
          : (member.toolName.isNotEmpty
                ? member.toolName
                : context.l10n.timelineToolCallFallback);
      final label = switch (reading.kind) {
        ToolCardUnavailableKind.malformed =>
          context.l10n.timelineToolMalformedLabel(name),
        ToolCardUnavailableKind.deferred =>
          context.l10n.timelineToolDeferredLabel(name),
      };
      final detail = switch (reading.kind) {
        ToolCardUnavailableKind.deferred =>
          context.l10n.timelineToolDeferredReason,
        ToolCardUnavailableKind.malformed =>
          reading.detail != null
              ? context.l10n.timelineToolParseFailed(reading.detail!)
              : reading.reason,
      };
      return _unavailable(label, detail);
    }

    final tool = workGroupToolPresentationFromMember(
      member,
      presentation: item,
      argumentsOverride: argumentsOverride,
      isLive: context.isLive,
    );
    final adapter = timelineToolItemRegistry.resolveForPresentation(tool);
    final outputReference = item.body('tool.result')?.feedReference;
    final feedContents = item.bodies.where(
      (body) =>
          body.feedReference != null &&
          !body.hasInline &&
          switch (body.key) {
            'tool.arguments' => adapter.bodyPolicy.readsArgumentsWindow,
            'tool.result' => adapter.readsOutput(
              tool.statusString,
              output: tool.output,
              toolData: tool.toolData,
            ),
            'tool.output-artifacts' => adapter.readsToolData,
            _ => false,
          },
    );

    final hasLiveTail =
        context.isLive &&
        isTimelineToolActive(tool.statusString) &&
        feedContents.every((body) => body.key != 'tool.result') &&
        (member.resultPreview?.trim().isNotEmpty ?? false);
    final hasAttachments =
        item.attachments.isNotEmpty && context.attachmentBuilder != null;

    WidgetBuilder? additionalBuilder;
    if (hasLiveTail || hasAttachments) {
      additionalBuilder = (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasLiveTail)
            StudioCodeBlock(
              text: member.resultPreview!,
              horizontalScroll: false,
            ),
          if (hasAttachments) context.attachmentBuilder!(item),
        ],
      );
    }

    return TimelineToolItemView(
      item: tool,
      workGroupMember: true,
      now: context.now,
      initiallyExpanded: context.initiallyExpanded,
      onExpansionChanged: context.onExpansionChanged,
      markdownBuilder: context.bodyBuilder,
      additionalContentBuilder: additionalBuilder,
      declaredContentIdentity: feedContents.isEmpty
          ? null
          : (
              outputReference,
              item.body('tool.output-artifacts')?.feedReference,
              true,
            ),
      declaredContentBuilder: feedContents.isEmpty
          ? null
          : (onOutputRead, onToolDataRead, acceptance) => [
              for (final body in feedContents)
                TimelineBodyReadIntent(
                  scrollable: true,
                  onRead: switch (body.key) {
                    'tool.result' => onOutputRead,
                    'tool.output-artifacts' => (window) => onToolDataRead(
                      body.key,
                      body.byteLength,
                      window,
                    ),
                    _ => null,
                  },
                  bodyBuilder: body.key == 'tool.output-artifacts'
                      ? (_) => const SizedBox.shrink()
                      : (text) => timelineToolWindowBody(
                          context.buildContext,
                          tool,
                          text,
                          input: body.key == 'tool.arguments',
                          markdownBuilder: context.bodyBuilder,
                          acceptance: acceptance,
                        ),
                  child: _buildWindowBody(context, item, body),
                ),
            ],
    );
  }

  Widget _buildWindowBody(
    WorkGroupMemberContext context,
    ChatItemPresentation item,
    ChatBodyPresentation body,
  ) {
    final id = '${item.id}:${body.key}';
    Widget render(String text) =>
        context.bodyBuilder?.call(id, text) ??
        TimelinePlainText(id: id, text: text);

    Widget witness(String text, Widget child) {
      final clock = context.monotonicMicros;
      final onLayout = context.onContentLayout;
      if (text.trim().isEmpty || clock == null || onLayout == null) {
        return child;
      }
      return ContentLayoutWitness(
        itemId: item.id,
        monotonicMicros: clock,
        onContentLayout: onLayout,
        isDisplayActive: context.isDisplayActive,
        child: child,
      );
    }

    return TimelineFeedBodyConnector(
      itemId: item.id,
      reference: body.feedReference!,
      label: '${body.key} · ${body.byteLength} 字节',
      disclosed: true,
      showCopy: true,
      bodyBuilder: render,
      witness: witness,
    );
  }

  Widget _unavailable(String title, String? detail) =>
      TimelineActivityTileTheme(
        child: TimelineActivityDisclosure(
          enabled: detail != null && detail.trim().isNotEmpty,
          titleBuilder: (_, expanded) => TimelineActivityRow(
            icon: Icons.info_outline,
            label: title,
            expanded: expanded,
            expandable: detail != null && detail.trim().isNotEmpty,
          ),
          children: [
            if (detail != null && detail.trim().isNotEmpty) Text(detail),
          ],
        ),
      );
}

TimelineToolPresentation _enrichToolTimestamps(
  TimelineToolPresentation base,
  WorkGroupToolCall member,
) {
  final createdAt = base.createdAt ?? _millisToDateTime(member.startedAtMs);
  final completedAt =
      base.completedAt ?? _millisToDateTime(member.finishedAtMs);
  if (createdAt == base.createdAt && completedAt == base.completedAt) {
    return base;
  }
  return TimelineToolPresentation(
    id: base.id,
    toolCallId: base.toolCallId,
    name: base.name,
    presentationContract: base.presentationContract,
    statusString: base.statusString,
    arguments: base.arguments,
    output: base.output,
    createdAt: createdAt,
    completedAt: completedAt,
    error: base.error,
    taskId: base.taskId,
    workingDirectory: base.workingDirectory,
    exitCode: base.exitCode,
    timedOut: base.timedOut,
    attachments: base.attachments,
    outputArtifacts: base.outputArtifacts,
    toolData: base.toolData,
    outputArtifactIdentity: base.outputArtifactIdentity,
    wait: base.wait,
    executionPresent: base.executionPresent,
    frozenObservation: base.frozenObservation,
  );
}

String _normalizeToolStatus(String status) => switch (status) {
  'completed' => 'succeeded',
  'waitingApproval' => 'awaitingApproval',
  _ => status,
};

bool _hasToolEnvelope(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == '{}') return false;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) return false;
    final data = decoded['data'];
    return data is Map<String, dynamic> && data.containsKey('invocation');
  } on FormatException {
    return false;
  }
}

DateTime? _millisToDateTime(int? ms) =>
    ms != null && ms.abs() <= 8640000000000000
    ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
    : null;

ThreadWaitPresentationView? _decodeWaitJson(String? waitJson) {
  if (waitJson == null || waitJson.trim().isEmpty) return null;
  try {
    final wait = jsonDecode(waitJson);
    if (wait is! Map<String, dynamic>) return null;
    final stateName = wait['state'];
    final state = ThreadWaitStateView.values
        .where((value) => value.name == stateName)
        .firstOrNull;
    final intent = wait['intent'];
    if (state == null || intent is! Map<String, dynamic>) return null;
    final intentKind = intent['kind'];
    final data = intent['data'];
    if (data is! Map<String, dynamic>) return null;
    final ThreadWaitIntentView? parsedIntent = switch (intentKind) {
      'timer' when data['durationMs'] is int => ThreadWaitTimerIntentView(
        durationMs: data['durationMs'] as int,
      ),
      'events' when data['timeoutMs'] is int && data['targets'] is List =>
        ThreadWaitEventsIntentView(
          timeoutMs: data['timeoutMs'] as int,
          targets: [
            for (final entry in data['targets'] as List)
              if (entry is Map<String, dynamic> && entry['taskId'] is String)
                ThreadWaitTargetView(
                  taskId: entry['taskId'] as String,
                  toolName: entry['toolName'] as String?,
                  summary: entry['summary'] as String?,
                  summaryTruncated: entry['summaryTruncated'] as bool? ?? false,
                  status: entry['status'] is String
                      ? ThreadWaitTargetStatusView.values
                            .where((value) => value.name == entry['status'])
                            .firstOrNull
                      : null,
                ),
          ],
        ),
      _ => null,
    };
    if (parsedIntent == null) return null;
    return ThreadWaitPresentationView(
      state: state,
      messagesReady: wait['messagesReady'] as bool?,
      intent: parsedIntent,
    );
  } on FormatException {
    return null;
  }
}
