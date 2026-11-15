import 'dart:convert';

import 'package:flutter/widget_previews.dart';
import 'package:material_ui/material_ui.dart';

import 'package:anywork/src/app/theme/material3_theme.dart';
import 'package:anywork/src/features/conversation/timeline/state/tool_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/state/timeline_file_presentation.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/completion_run_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_attachments_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_image_view.dart';
import 'package:anywork/src/features/conversation/timeline/widgets/timeline_tool_blocks.dart';
import 'package:anywork/src/l10n/app_localizations.dart';

import 'conversation_live_status_previews.dart';
import 'tool_detail_preview_fixtures.dart';
import 'timeline_preview_fixtures.dart';

Widget _toolHost(
  Widget child, {
  double scale = 1,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  locale: const Locale('zh'),
  theme: _theme(brightness),
  localizationsDelegates: [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  builder: (context, appChild) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: ListTileTheme(
      data: Theme.of(context).listTileTheme,
      child: appChild!,
    ),
  ),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: child,
        ),
      ),
    ),
  ),
);

ThemeData _theme(Brightness brightness) {
  final base = pureStudioTheme(locale: const Locale('zh'));
  if (brightness == Brightness.light) return base;
  final scheme = ColorScheme.fromSeed(
    seedColor: base.colorScheme.primary,
    brightness: brightness,
  );
  return base.copyWith(
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
  );
}

ToolDetailPreviewFixture _fixture(String contract) =>
    toolDetailPreviewFixtures.singleWhere((f) => f.contract == contract);

Widget _tool(String contract, {bool expanded = true}) {
  final fixture = _fixture(contract);
  final item = fixture.toPresentation('preview-${fixture.name}');
  return _toolHost(
    TimelineToolDetails(
      item: item,
      initiallyExpanded: expanded,
      additionalContentBuilder:
          item.attachments.isEmpty && item.outputArtifacts.isEmpty
          ? null
          : (_) => toolDetailPreviewMediaSlot(item),
    ),
  );
}

Widget toolDetailPreviewMediaSlot(TimelineToolPresentation item) {
  final files = item.outputArtifacts.isEmpty
      ? null
      : TimelineFilesPresentation.fromArtifacts(item.outputArtifacts.single);
  final attachments = files == null
      ? item.attachments
      : [for (final file in files.files) ?file.attachment];
  return TimelineAttachmentsView(
    attachments: attachments,
    files: files?.files,
    caption: files?.caption ?? '工具返回的合成图片附件',
    imageBuilder: (attachment) => TimelineImageView(
      itemId: item.id,
      attachment: attachment,
      isTool: true,
      active: true,
      imageIdentity: ('tool-media-preview', attachment.id),
      bytes: TimelinePreviewFixtures.imageBytes,
      width: TimelinePreviewFixtures.imageWidth,
      height: TimelinePreviewFixtures.imageHeight,
    ),
  );
}

@Preview(name: '工具展开 / exec', group: '工具详情', size: Size(960, 640))
Widget execToolDetailPreview() => _tool('builtin.exec@2');
@Preview(name: '工具展开 / write_stdin', group: '工具详情', size: Size(960, 640))
Widget writeStdinToolDetailPreview() => _tool('builtin.write_stdin@1');
@Preview(name: '工具展开 / read_session_note', group: '工具详情', size: Size(960, 640))
Widget readSessionNoteToolDetailPreview() =>
    _tool('builtin.read_session_note@1');
@Preview(
  name: '工具展开 / search_session_note',
  group: '工具详情',
  size: Size(960, 640),
)
Widget searchSessionNoteToolDetailPreview() =>
    _tool('builtin.search_session_note@1');
@Preview(name: '工具展开 / write_session_note', group: '工具详情', size: Size(960, 640))
Widget writeSessionNoteToolDetailPreview() =>
    _tool('builtin.write_session_note@1');
@Preview(
  name: '工具展开 / apply_session_note_patch',
  group: '工具详情',
  size: Size(960, 640),
)
Widget applySessionNotePatchToolDetailPreview() =>
    _tool('builtin.apply_session_note_patch@1');
@Preview(name: '工具展开 / stat_path', group: '工具详情', size: Size(960, 640))
Widget statPathToolDetailPreview() => _tool('builtin.stat_path@1');
@Preview(name: '工具展开 / write_file', group: '工具详情', size: Size(960, 640))
Widget writeFileToolDetailPreview() => _tool('builtin.write_file@1');
@Preview(name: '工具展开 / apply_patch', group: '工具详情', size: Size(960, 640))
Widget applyPatchToolDetailPreview() => _tool('builtin.apply_patch@1');
@Preview(name: '工具展开 / create_directory', group: '工具详情', size: Size(960, 640))
Widget createDirectoryToolDetailPreview() =>
    _tool('builtin.create_directory@1');
@Preview(name: '工具展开 / delete_path', group: '工具详情', size: Size(960, 640))
Widget deletePathToolDetailPreview() => _tool('builtin.delete_path@1');
@Preview(name: '工具展开 / copy_path', group: '工具详情', size: Size(960, 640))
Widget copyPathToolDetailPreview() => _tool('builtin.copy_path@1');
@Preview(name: '工具展开 / move_path', group: '工具详情', size: Size(960, 640))
Widget movePathToolDetailPreview() => _tool('builtin.move_path@1');
@Preview(name: '工具展开 / spawn_agent', group: '工具详情', size: Size(960, 640))
Widget spawnAgentToolDetailPreview() => _tool('builtin.spawn_agent@1');
@Preview(name: '工具展开 / send_message', group: '工具详情', size: Size(960, 640))
Widget sendMessageToolDetailPreview() => _tool('builtin.send_message@1');
@Preview(name: '工具展开 / wait', group: '工具详情', size: Size(960, 640))
Widget waitToolDetailPreview() => _tool('builtin.wait@1');
@Preview(name: '工具展开 / sleep', group: '工具详情', size: Size(960, 640))
Widget sleepToolDetailPreview() => _tool('builtin.sleep@1');
@Preview(name: '工具展开 / view_image', group: '工具详情', size: Size(960, 640))
Widget viewImageToolDetailPreview() => _tool('builtin.view_image@1');
@Preview(name: '工具展开 / show_files', group: '工具详情', size: Size(960, 640))
Widget showFilesToolDetailPreview() => _tool('builtin.show_files@1');
@Preview(name: '工具展开 / lsp_query', group: '工具详情', size: Size(960, 640))
Widget lspQueryToolDetailPreview() => _tool('builtin.lsp_query@1');
@Preview(name: '工具展开 / lsp_capabilities', group: '工具详情', size: Size(960, 640))
Widget lspCapabilitiesToolDetailPreview() =>
    _tool('builtin.lsp_capabilities@1');
@Preview(name: '工具展开 / lsp_status', group: '工具详情', size: Size(960, 640))
Widget lspStatusToolDetailPreview() => _tool('builtin.lsp_status@1');
@Preview(name: '工具展开 / plan_current', group: '工具详情', size: Size(960, 640))
Widget planCurrentToolDetailPreview() => _tool('builtin.plan_current@1');
@Preview(name: '工具展开 / plan_next', group: '工具详情', size: Size(960, 640))
Widget planNextToolDetailPreview() => _tool('builtin.plan_next@1');
@Preview(name: '工具展开 / plan_history', group: '工具详情', size: Size(960, 640))
Widget planHistoryToolDetailPreview() => _tool('builtin.plan_history@1');
@Preview(name: '工具展开 / plan_submit', group: '工具详情', size: Size(960, 640))
Widget planSubmitToolDetailPreview() => _tool('builtin.plan_submit@1');
@Preview(name: '工具展开 / plan_restart', group: '工具详情', size: Size(960, 640))
Widget planRestartToolDetailPreview() => _tool('builtin.plan_restart@1');
@Preview(name: '工具展开 / workflow_current', group: '工具详情', size: Size(960, 640))
Widget workflowCurrentToolDetailPreview() =>
    _tool('builtin.workflow_current@1');
@Preview(name: '工具展开 / workflow_next', group: '工具详情', size: Size(960, 640))
Widget workflowNextToolDetailPreview() => _tool('builtin.workflow_next@1');
@Preview(name: '工具展开 / workflow_graph', group: '工具详情', size: Size(960, 640))
Widget workflowGraphToolDetailPreview() => _tool('builtin.workflow_graph@1');
@Preview(name: '工具展开 / workflow_history', group: '工具详情', size: Size(960, 640))
Widget workflowHistoryToolDetailPreview() =>
    _tool('builtin.workflow_history@1');
@Preview(
  name: '工具展开 / workflow_transition',
  group: '工具详情',
  size: Size(960, 640),
)
Widget workflowTransitionToolDetailPreview() =>
    _tool('builtin.workflow_transition@1');
@Preview(name: '工具展开 / workflow_restart', group: '工具详情', size: Size(960, 640))
Widget workflowRestartToolDetailPreview() =>
    _tool('builtin.workflow_restart@1');
@Preview(name: '工具展开 / web_search', group: '工具详情', size: Size(960, 640))
Widget webSearchToolDetailPreview() => _tool('builtin.web_search@1');
@Preview(
  name: '工具展开 / deepseek_web_search',
  group: '工具详情',
  size: Size(960, 640),
)
Widget deepseekWebSearchToolDetailPreview() =>
    _tool('builtin.deepseek_web_search@1');
@Preview(name: '工具展开 / deepseek_web_fetch', group: '工具详情', size: Size(960, 640))
Widget deepseekWebFetchToolDetailPreview() =>
    _tool('builtin.deepseek_web_fetch@1');
@Preview(name: '工具展开 / generic@1', group: '工具详情', size: Size(960, 640))
Widget genericToolDetailPreview() => _tool('generic@1');

@Preview(name: '工具详情 / 失败状态', group: '工具详情', size: Size(960, 640))
Widget failedToolDetailPreview() => _toolHost(
  TimelineToolDetails(
    item: failedToolPreviewFixture.toPresentation('preview-failed-web-search'),
    initiallyExpanded: true,
  ),
);
@Preview(name: '工具详情 / 执行超时', group: '工具详情', size: Size(960, 640))
Widget timedOutToolDetailPreview() => _toolHost(
  TimelineToolDetails(
    item: timedOutToolPreviewFixture.toPresentation('preview-timeout-exec'),
    initiallyExpanded: true,
  ),
);

@Preview(name: '工具详情 / 窄屏 390', group: '工具详情', size: Size(390, 760))
Widget narrowToolDetailPreview() => _toolHost(
  TimelineToolDetails(
    item: _fixture('builtin.web_search@1')
        .toPresentation('preview-narrow-search'),
    initiallyExpanded: true,
  ),
);
@Preview(name: '工具详情 / 字号 160%', group: '工具详情', size: Size(960, 760))
Widget largeTextToolDetailPreview() => _toolHost(
  TimelineToolDetails(
    item: _fixture('builtin.deepseek_web_search@1')
        .toPresentation('preview-large-text-search'),
    initiallyExpanded: true,
  ),
  scale: 1.6,
);
@Preview(
  name: '工具详情 / 暗色',
  group: '工具详情',
  size: Size(960, 640),
  brightness: Brightness.dark,
)
Widget darkToolDetailPreview() => _toolHost(
  TimelineToolDetails(
    item: _fixture('builtin.exec@2').toPresentation('preview-dark-exec'),
    initiallyExpanded: true,
  ),
  brightness: Brightness.dark,
);
@Preview(name: '工具详情 / 长结果', group: '工具详情', size: Size(960, 640))
Widget longToolResultPreview() {
  final base = _fixture('builtin.deepseek_web_search@1');
  final item = base.toPresentation('preview-long-search');
  return _toolHost(
    TimelineToolDetails(
      item: TimelineToolPresentation(
        id: item.id,
        toolCallId: item.toolCallId,
        name: item.name,
        presentationContract: item.presentationContract,
        statusString: item.statusString,
        arguments: item.arguments,
        output: jsonEncode({
          'queries': base.arguments['queries'],
          'responses': [
            {
              'sources': [
                for (var index = 1; index <= 24; index++)
                  {
                    'url': 'https://example.com/docs/widget-preview#$index',
                    'title': '组件预览文档 $index',
                    'snippet': '第 $index 条结果：在合成文档中找到与查询相关的段落，并保留来源标题。',
                  },
              ],
            },
          ],
        }),
        taskId: item.taskId,
      ),
      initiallyExpanded: true,
    ),
  );
}

@Preview(name: '工作组 / 活动行无正文', group: '工具详情', size: Size(960, 640))
Widget emptyActivityRowToolPreview() =>
    _toolHost(liveStatusGroupPreview(thinkingOnly: true));
@Preview(name: '工作组 / 已折叠', group: '工具详情', size: Size(960, 640))
Widget collapsedWorkGroupToolPreview() =>
    _toolHost(liveStatusGroupPreview(history: true));
@Preview(name: '工作组 / 展开与滚动', group: '工具详情', size: Size(960, 640))
Widget expandedWorkGroupScrollToolPreview() => _toolHost(
  CompletionRunView(
    key: const ValueKey('preview-tool-workgroup'),
    id: 'preview-tool-workgroup',
    timing: TimelinePreviewFixtures.workTiming(),
    initiallyExpanded: true,
    location: WorkDisplayLocation.history,
    childBuilder: (_) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final fixture in [
          toolDetailPreviewFixtures.first,
          toolDetailPreviewFixtures[19],
          toolDetailPreviewFixtures[33],
        ])
          TimelineToolDetails(
            item: fixture.toPresentation('preview-group-${fixture.name}'),
            initiallyExpanded: true,
          ),
      ],
    ),
  ),
);
