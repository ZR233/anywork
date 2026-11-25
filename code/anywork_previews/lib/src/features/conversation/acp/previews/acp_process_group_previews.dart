import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/timeline/state/patch_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_activity_row.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

Widget _shell(Widget child, {ThemeData? theme}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: theme ?? pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Widget _labeledSection(String title, Widget child) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  mainAxisSize: MainAxisSize.min,
  children: [
    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Builder(
        builder: (context) => Text(
          title,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ),
    child,
    const SizedBox(height: 12),
  ],
);

AcpTimelineProcessRow sampleAcpProcessRow({
  String id = 'preview:process',
  AcpToolStatusKind status = AcpToolStatusKind.completed,
  bool longContent = false,
}) {
  final longLine = List.filled(12, '长内容保持完整并随会话换行。').join();
  final arguments = longContent
      ? List.generate(18, (index) => '参数 $index: $longLine').join('\n')
      : '{\n  "path": "lib/conversation.dart",\n  "reason": "修复过程展示"\n}';
  return AcpTimelineProcessRow(
    id: id,
    items: [
      AcpTimelineThoughtItem(
        id: '$id:thought',
        summary: '核对接口与调用链',
        blocks: [
          AcpTextBlockPresentation(
            text: longContent ? '思考正文：$longLine' : '先确认消息边界，再保留每项工具详情。',
          ),
        ],
      ),
      AcpTimelineToolCallItem(
        id: '$id:tool',
        toolCallId: '$id:call',
        status: status,
        kindLabel: 'edit',
        rawName: 'replace_file_content',
        locations: [
          'code/anywork/lib/src/features/conversation/acp/views/acp_conversation_content_view.dart:42',
        ],
        terminals: ['terminal-1'],
        tool: TimelineToolPresentation(
          id: '$id:tool',
          toolCallId: '$id:call',
          name: '更新过程展示',
          presentationContract: 'acp.tool.edit',
          statusString: switch (status) {
            AcpToolStatusKind.completed => 'succeeded',
            AcpToolStatusKind.failed => 'failed',
            AcpToolStatusKind.pending => 'pending',
            AcpToolStatusKind.inProgress => 'running',
            AcpToolStatusKind.unknown => 'unknown',
          },
          arguments: arguments,
          output: status == AcpToolStatusKind.failed
              ? '验证失败：权限不足，原文件未改动。'
              : longContent
              ? '完整输出开始\n$arguments\n完整输出结束'
              : '已更新 1 个文件，检查通过。',
        ),
        diffs: [
          TimelinePatchDocument(
            files: [
              TimelinePatchFile(
                op: TimelinePatchFileOp.update,
                path: 'lib/conversation.dart',
                chunks: [
                  TimelinePatchChunk(
                    context: '过程内容展示',
                    lines: [
                      const TimelinePatchLine(
                        kind: TimelinePatchLineKind.deletion,
                        text: 'return oldView;',
                      ),
                      TimelinePatchLine(
                        kind: TimelinePatchLineKind.addition,
                        text: longContent
                            ? 'return "$longLine";'
                            : 'return processGroup;',
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
        contentBlocks: [
          AcpTextResourceBlockPresentation(
            uri: 'resource://verification/details',
            mimeType: 'text/plain',
            text: longContent
                ? '嵌入文本开始\n$arguments\n嵌入文本结束'
                : '检查记录：参数、输出与补丁同时显示。',
          ),
          if (longContent) ...[
            AcpTextBlockPresentation(text: '```text\n$longLine\n```'),
            const AcpResourceLinkBlockPresentation(
              label: '官方验证参考资料',
              uri: 'https://example.com/verification/complete-report',
              mimeType: 'text/html',
              canOpenExternal: true,
              description: '外部链接仅由用户操作打开。',
            ),
            const AcpAudioBlockPresentation(mimeType: 'audio/wav'),
            const AcpBlobResourceBlockPresentation(
              uri: 'resource://verification/archive',
              mimeType: 'application/zip',
              byteCount: 1024,
            ),
          ],
        ],
      ),
      AcpTimelineSessionUpdateItem(
        id: '$id:notice',
        update: const AcpNoticeUpdatePresentation(
          title: '检查记录已保存',
          description: '本组包含思考、工具与会话通知。',
        ),
      ),
    ],
  );
}

AcpTimelineProcessRow sampleAcpRichExpandedRow({
  String id = 'preview:matrix',
}) => AcpTimelineProcessRow(
  id: id,
  items: [
    AcpTimelineThoughtItem(
      id: '$id:thought',
      summary: '先排查 **acp_tool_card** 与 `AcpTimelineProcessGroupView` 的复用边界',
      blocks: const [
        AcpTextBlockPresentation(
          text: '确认两点：\n1. 组标题复用单行 `TimelineActivityRow`；\n2. 工具成员统一走 `TimelineToolItemView`。',
        ),
      ],
    ),
    AcpTimelineToolCallItem(
      id: '$id:read',
      toolCallId: '$id:call-read',
      status: AcpToolStatusKind.completed,
      kindLabel: 'read',
      rawName: 'read_file',
      locations: const [
        'code/anywork/lib/src/features/conversation/acp/widgets/acp_tool_card.dart:1',
      ],
      tool: TimelineToolPresentation(
        id: '$id:read',
        toolCallId: '$id:call-read',
        name: '读取 acp_tool_card.dart',
        presentationContract: 'acp.tool.read',
        statusString: 'succeeded',
        arguments: '{\n  "path": "acp_tool_card.dart",\n  "lines": "1-120"\n}',
        output: 'class AcpToolCard extends StatelessWidget { ... }',
      ),
    ),
    AcpTimelineToolCallItem(
      id: '$id:search',
      toolCallId: '$id:call-search',
      status: AcpToolStatusKind.completed,
      kindLabel: 'search',
      tool: TimelineToolPresentation(
        id: '$id:search',
        toolCallId: '$id:call-search',
        name: '搜索 TimelineActivityDisclosure 调用方',
        presentationContract: 'acp.tool.search',
        statusString: 'succeeded',
        arguments: '{\n  "query": "TimelineActivityDisclosure",\n  "scope": "conversation/"\n}',
        output: '命中 6 个文件，共 14 处引用。',
      ),
    ),
    AcpTimelineToolCallItem(
      id: '$id:exec-fail',
      toolCallId: '$id:call-exec-fail',
      status: AcpToolStatusKind.failed,
      kindLabel: 'execute',
      terminals: const ['term-test-1'],
      tool: TimelineToolPresentation(
        id: '$id:exec-fail',
        toolCallId: '$id:call-exec-fail',
        name: 'flutter test test/ui/acp_process_group_test.dart',
        presentationContract: 'acp.tool.execute',
        statusString: 'failed',
        arguments:
            'cargo flutter test --no-pub test/ui/acp_process_group_test.dart',
        output: 'Exit code 1: expected 1 assertion update in legacy ExpansionTile test.',
      ),
    ),
    AcpTimelineToolCallItem(
      id: '$id:thin-think',
      toolCallId: '$id:call-think',
      status: AcpToolStatusKind.completed,
      kindLabel: 'think',
      tool: TimelineToolPresentation(
        id: '$id:thin-think',
        toolCallId: '$id:call-think',
        name: '确认无详情轻量工具不可展开',
        presentationContract: 'acp.tool.think',
        statusString: 'succeeded',
        arguments: '',
        output: '',
      ),
    ),
    sampleAcpProcessRow(id: '$id:edit-source').items[1],
  ],
);

Widget _runningStatesBody() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  mainAxisSize: MainAxisSize.min,
  children: [
    _labeledSection(
      '1. 运行中 · 命令执行工具（蓝色进度环 + 工具名 + 计数）',
      AcpTimelineProcessGroupView(
        row: AcpTimelineProcessRow(
          id: 'run:exec',
          items: const [
            AcpTimelineThoughtItem(
              id: 'run:exec:thought',
              summary: '运行单元测试验证改动',
              blocks: [AcpTextBlockPresentation(text: '准备跑测试')],
            ),
            AcpTimelineToolCallItem(
              id: 'run:exec:tool',
              toolCallId: 'call-exec',
              status: AcpToolStatusKind.inProgress,
              kindLabel: 'execute',
              tool: TimelineToolPresentation(
                id: 'run:exec:tool',
                toolCallId: 'call-exec',
                name: 'cargo flutter test --no-pub test/ui/acp_process_group_test.dart',
                presentationContract: 'acp.tool.execute',
                statusString: 'running',
                arguments: '',
                output: '',
              ),
            ),
          ],
        ),
      ),
    ),
    _labeledSection(
      '2. 运行中 · 文件读取 / 编辑工具（摆尾猫 + 工具名 + 计数）',
      AcpTimelineProcessGroupView(
        row: sampleAcpProcessRow(
          id: 'run:edit',
          status: AcpToolStatusKind.inProgress,
        ),
      ),
    ),
    _labeledSection(
      '3. 运行中 · 思考流（摆尾猫 + Markdown 单行摘要）',
      AcpTimelineProcessGroupView(
        row: AcpTimelineProcessRow(
          id: 'run:thought',
          items: const [
            AcpTimelineThoughtItem(
              id: 'run:thought:item',
              summary: '正在比对 `CompletionRunView` 与 **AcpToolCard** 的行高契约',
              active: true,
              blocks: [
                AcpTextBlockPresentation(
                  text: '正在比对 `CompletionRunView` 与 **AcpToolCard** 的行高契约\n补充思考详情。',
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    _labeledSection(
      '4. 运行中 · 上下文压缩（拉链动效）',
      AcpTimelineProcessGroupView(
        row: AcpTimelineProcessRow(
          id: 'run:compact',
          items: const [
            AcpTimelineSessionUpdateItem(
              id: 'run:compact:item',
              update: AcpCompactionUpdatePresentation(
                statusLabel: '进行中',
                inProgress: true,
              ),
            ),
          ],
        ),
      ),
    ),
  ],
);

Widget _completedStatesBody() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  mainAxisSize: MainAxisSize.min,
  children: [
    _labeledSection(
      '1. 已完成折叠 · 纯思考过程组',
      AcpTimelineProcessGroupView(
        row: AcpTimelineProcessRow(
          id: 'done:thoughts',
          items: const [
            AcpTimelineThoughtItem(
              id: 'done:t1',
              summary: '梳理分组边界',
              blocks: [AcpTextBlockPresentation(text: '梳理分组边界')],
            ),
            AcpTimelineThoughtItem(
              id: 'done:t2',
              summary: '核对测试断言',
              blocks: [AcpTextBlockPresentation(text: '核对测试断言')],
            ),
          ],
        ),
      ),
    ),
    _labeledSection(
      '2. 已完成折叠 · 纯工具过程组',
      AcpTimelineProcessGroupView(
        row: AcpTimelineProcessRow(
          id: 'done:tools',
          items: sampleAcpRichExpandedRow().items
              .whereType<AcpTimelineToolCallItem>()
              .take(3)
              .toList(),
        ),
      ),
    ),
    _labeledSection(
      '3. 已完成折叠 · 混合过程组（思考 + 工具 + 通知）',
      AcpTimelineProcessGroupView(row: sampleAcpProcessRow(id: 'done:mixed')),
    ),
    _labeledSection(
      '4. 已完成折叠 · 含失败工具（保持中性外观，不染红强调）',
      AcpTimelineProcessGroupView(
        row: sampleAcpProcessRow(
          id: 'done:failed',
          status: AcpToolStatusKind.failed,
        ),
      ),
    ),
  ],
);

@Preview(name: '工况 1 · 运行中合集', group: 'ACP 过程', size: Size(760, 420))
Widget acpProcessGroupRunningStatesPreview() => _shell(
  LiveStatusMotionHost(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _runningStatesBody(),
    ),
  ),
);

@Preview(name: '工况 2 · 已完成折叠合集', group: 'ACP 过程', size: Size(760, 420))
Widget acpProcessGroupCompletedStatesPreview() => _shell(
  LiveStatusMotionHost(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _completedStatesBody(),
    ),
  ),
);

@Preview(name: '工况 3 · 已展开过程组与多类工具矩阵', group: 'ACP 过程', size: Size(820, 760))
Widget acpProcessGroupExpandedMatrixPreview() => _shell(
  LiveStatusMotionHost(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: AcpTimelineProcessGroupView(
        row: sampleAcpRichExpandedRow(),
        initiallyExpanded: true,
      ),
    ),
  ),
);

@Preview(name: '过程组 · 默认折叠', group: 'ACP 过程', size: Size(760, 200))
Widget acpProcessGroupCollapsedPreview() => _shell(
  LiveStatusMotionHost(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AcpTimelineProcessGroupView(
          row: sampleAcpProcessRow(id: 'preview:collapsed'),
        ),
      ),
    ),
  ),
);

@Preview(name: '过程组 · 点击展开', group: 'ACP 过程', size: Size(760, 720))
Widget acpProcessGroupExpandablePreview() => _shell(
  LiveStatusMotionHost(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AcpTimelineProcessGroupView(
          row: sampleAcpProcessRow(id: 'preview:interactive'),
        ),
      ),
    ),
  ),
);

@Preview(name: '过程组 · 执行中', group: 'ACP 过程', size: Size(760, 200))
Widget acpProcessGroupRunningPreview() => _shell(
  LiveStatusMotionHost(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AcpTimelineProcessGroupView(
          row: sampleAcpProcessRow(
            id: 'preview:running',
            status: AcpToolStatusKind.inProgress,
          ),
        ),
      ),
    ),
  ),
);

@Preview(name: '过程组 · 失败仍折叠', group: 'ACP 过程', size: Size(760, 200))
Widget acpProcessGroupFailedPreview() => _shell(
  LiveStatusMotionHost(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AcpTimelineProcessGroupView(
          row: sampleAcpProcessRow(
            id: 'preview:failed',
            status: AcpToolStatusKind.failed,
          ),
        ),
      ),
    ),
  ),
);

@Preview(name: '过程组 · 失败详情', group: 'ACP 过程', size: Size(760, 720))
Widget acpProcessGroupFailedDetailsPreview() => _shell(
  LiveStatusMotionHost(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AcpTimelineProcessGroupView(
          row: sampleAcpProcessRow(
            id: 'preview:failed-details',
            status: AcpToolStatusKind.failed,
          ),
          initiallyExpanded: true,
        ),
      ),
    ),
  ),
);

@Preview(name: '过程组 · 长内容展开', group: 'ACP 过程', size: Size(760, 720))
Widget acpProcessGroupLongPreview() => _shell(
  LiveStatusMotionHost(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: AcpTimelineProcessGroupView(
          row: sampleAcpProcessRow(id: 'preview:long', longContent: true),
          initiallyExpanded: true,
        ),
      ),
    ),
  ),
);

Widget sampleAcpConversation({
  bool expanded = true,
  String id = 'preview-conversation',
}) {
  final rows = <AcpTimelineRow>[
    const AcpTimelineMessageRow(
      AcpTimelineUserMessage(
        id: 'user',
        blocks: [AcpTextBlockPresentation(text: '请检查并修复过程展示。')],
      ),
    ),
    const AcpTimelineMessageRow(
      AcpTimelineAssistantMessage(
        id: 'progress-1',
        blocks: [AcpTextBlockPresentation(text: '正在核对现有实现，随后验证参数、输出与补丁。')],
      ),
    ),
    sampleAcpProcessRow(id: '$id:progress-1:process'),
    const AcpTimelineMessageRow(
      AcpTimelineAssistantMessage(
        id: 'progress-2',
        blocks: [AcpTextBlockPresentation(text: '接口已确认。接下来运行长内容与窄窗口验证。')],
      ),
    ),
    sampleAcpProcessRow(
      id: '$id:progress-2:process',
      status: AcpToolStatusKind.failed,
      longContent: true,
    ),
    const AcpTimelineMessageRow(
      AcpTimelineAssistantMessage(
        id: 'result',
        blocks: [AcpTextBlockPresentation(text: '本轮验证结束，失败详情保留在过程组中。')],
      ),
    ),
  ];
  return AcpConversationContentView(
    threadId: id,
    header: const AcpTimelineHeaderViewState(
      ready: true,
      loading: false,
      hasConversationalContent: true,
    ),
    rows: rows,
    itemBuilder: (context, row) => switch (row) {
      AcpTimelineMessageRow(:final item) => AcpTimelineEntryView(item: item),
      final AcpTimelineProcessRow row => AcpTimelineProcessGroupView(
        row: row,
        initiallyExpanded: expanded,
      ),
    },
  );
}

@Preview(name: '完整会话 · 多组展开', group: 'ACP 过程', size: Size(1000, 800))
Widget acpProcessConversationPreview() =>
    _shell(sampleAcpConversation(id: 'preview-conversation-wide'));

@Preview(
  name: '完整会话 · 窄窗大字',
  group: 'ACP 过程',
  size: Size(340, 740),
  textScaleFactor: 1.8,
)
Widget acpProcessConversationNarrowPreview() =>
    _shell(sampleAcpConversation(id: 'preview-conversation-narrow'));

@Preview(name: '完整会话 · 可见进展与折叠过程', group: 'ACP 过程', size: Size(900, 720))
Widget acpProcessConversationCollapsedPreview() => _shell(
  sampleAcpConversation(expanded: false, id: 'preview-conversation-collapsed'),
);
