import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/acp/acp_views.dart';
import 'package:anywork/src/features/conversation/timeline/state/patch_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/l10n/app_localizations.dart';
import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

Widget _shell(Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: pureStudioTheme(),
  locale: const Locale('zh'),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

AcpTimelineProcessRow sampleAcpProcessRow({
  String id = 'preview:process',
  AcpToolStatusKind status = AcpToolStatusKind.completed,
  bool longContent = false,
}) {
  final longLine = List.filled(12, '长内容保持完整并随会话换行。').join();
  final arguments = longContent
      ? List.generate(18, (index) => '参数 $index: $longLine').join('\n')
      : '{"path":"lib/conversation.dart","reason":"修复过程展示"}';
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
        locations: [
          'code/anywork/lib/src/features/conversation/acp/views/acp_conversation_content_view.dart:42',
        ],
        terminals: ['terminal-1'],
        tool: TimelineToolPresentation(
          id: '$id:tool',
          toolCallId: '$id:call',
          name: '更新过程展示',
          presentationContract: 'acp.tool',
          statusString: status == AcpToolStatusKind.failed
              ? 'failed'
              : 'succeeded',
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

@Preview(name: '过程组 · 默认折叠', group: 'ACP 过程', size: Size(760, 200))
Widget acpProcessGroupCollapsedPreview() => _shell(
  SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: AcpTimelineProcessGroupView(
        row: sampleAcpProcessRow(id: 'preview:collapsed'),
      ),
    ),
  ),
);

@Preview(name: '过程组 · 点击展开', group: 'ACP 过程', size: Size(760, 720))
Widget acpProcessGroupExpandablePreview() => _shell(
  SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: AcpTimelineProcessGroupView(
        row: sampleAcpProcessRow(id: 'preview:interactive'),
      ),
    ),
  ),
);

@Preview(name: '过程组 · 执行中', group: 'ACP 过程', size: Size(760, 200))
Widget acpProcessGroupRunningPreview() => _shell(
  SingleChildScrollView(
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
);

@Preview(name: '过程组 · 失败仍折叠', group: 'ACP 过程', size: Size(760, 200))
Widget acpProcessGroupFailedPreview() => _shell(
  SingleChildScrollView(
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
);

@Preview(name: '过程组 · 长内容全部展开', group: 'ACP 过程', size: Size(760, 720))
Widget acpProcessGroupLongPreview() => _shell(
  SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: AcpTimelineProcessGroupView(
        row: sampleAcpProcessRow(id: 'preview:long', longContent: true),
        initiallyExpanded: true,
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
    header: AcpTimelineHeaderViewState(
      ready: true,
      loading: false,
      hasConversationalContent: true,
      itemCount: rows.length,
    ),
    itemBuilder: (context, index) => switch (rows[index]) {
      AcpTimelineMessageRow(:final item) => AcpTimelineEntryView(
        key: ValueKey(item.id),
        item: item,
      ),
      final AcpTimelineProcessRow row => AcpTimelineProcessGroupView(
        key: ValueKey(row.id),
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
